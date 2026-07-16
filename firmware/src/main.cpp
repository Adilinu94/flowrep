// FlowRep firmware - M5StickC Plus2
//
// Switched from Bluedroid to NimBLE (h2zero/NimBLE-Arduino) because
// Bluedroid silently drops/fragments 52-byte notifications after the
// first one, even when MTU is negotiated to 517. The M5StickCPlus2
// display confirmed: loop() and notify() keep running fine, but
// notifications never reach the Flutter app beyond batch 1.
// NimBLE handles large notifications correctly on ESP32.

#include <math.h>
#include <M5StickCPlus2.h>
#include <NimBLEDevice.h>

// UUIDs MUST match app/lib/data/providers/ble_sensor_provider.dart exactly.
// docs/protocol.yaml is the source of truth for the wire format itself;
// these UUID strings are the GATT addressing on top of that format.
#define SERVICE_UUID           "0000fee0-0000-1000-8000-00805f9b34fb"
#define SENSOR_DATA_CHAR_UUID  "0000fee1-0000-1000-8000-00805f9b34fb"
#define CONTROL_POINT_CHAR_UUID "0000fee2-0000-1000-8000-00805f9b34fb"
#define BATTERY_CHAR_UUID      "0000fee3-0000-1000-8000-00805f9b34fb"

#define DEVICE_NAME "GymTracker"
#define SAMPLE_RATE_HZ 50
#define SAMPLES_PER_BATCH 4

// Must match docs/protocol.yaml exactly: 4-byte timestamp + 4 samples of
// 12 bytes each (3x int16 accel + 3x int16 gyro) = 52 bytes total.
#pragma pack(push, 1)
struct SensorSampleWire {
  int16_t ax, ay, az;  // scale 0.001 -> g
  int16_t gx, gy, gz;  // scale 0.01  -> deg/s
};
struct SensorBatchWire {
  uint32_t timestamp;
  SensorSampleWire samples[SAMPLES_PER_BATCH];
};
#pragma pack(pop)

static_assert(sizeof(SensorBatchWire) == 52,
              "SensorBatchWire must match docs/protocol.yaml exactly (52 bytes)");

NimBLEServer* server = nullptr;
NimBLECharacteristic* sensorDataChar = nullptr;
NimBLECharacteristic* controlPointChar = nullptr;
NimBLECharacteristic* batteryChar = nullptr;

bool deviceConnected = false;
bool streaming = false;
volatile bool dummyStream = false;  // Debug: send constant dummy batches without IMU
unsigned long streamStartDelay = 0;  // defer stream start to avoid GATT race
const unsigned long STREAM_START_DELAY_MS = 500;
SensorBatchWire currentBatch;
uint8_t sampleIndexInBatch = 0;
unsigned long lastSampleMicros = 0;
const unsigned long sampleIntervalMicros = 1000000UL / SAMPLE_RATE_HZ;

// Debug state displayed on the M5StickCPlus2 screen.
struct DebugState {
  unsigned long loopCount = 0;
  unsigned long batchesSent = 0;
  unsigned long imuFailures = 0;
  unsigned long setValueCount = 0;  // counts setValue() calls (replaces notifyFailures)
  unsigned int subscribedCount = 0;
  unsigned long lastDisplayUpdate = 0;
  unsigned long lastSerialDump = 0;  // throttle Serial IMU dumps to ~1 Hz
  char lastStatus[32] = "boot";
  bool needsRefresh = true;
  // Stale-data detection: if IMU returns identical values for many reads, I2C hung
  float lastAx = 0, lastAy = 0, lastAz = 0, lastGx = 0, lastGy = 0, lastGz = 0;
  unsigned int staleReadCount = 0;
  bool staleWarned = false;
} debugState;

// M5StickCPlus2 uses AXP2101 PMIC. getBatteryLevel() returns 0 (HW bug).
// FIXED: voltage-based calculation instead — LiPo full=4200mV, empty=3300mV.
uint8_t getBatteryPercent() {
  int voltage = M5.Power.getBatteryVoltage();
  return map(constrain(voltage, 3300, 4200), 3300, 4200, 0, 100);
}

void updateDisplayStatus(const char* status) {
  strncpy(debugState.lastStatus, status, sizeof(debugState.lastStatus) - 1);
  debugState.lastStatus[sizeof(debugState.lastStatus) - 1] = '\0';
  debugState.needsRefresh = true;
}

void renderDisplay() {
  M5.Display.fillScreen(BLACK);
  M5.Display.setCursor(0, 0);
  M5.Display.printf("%s\n", debugState.lastStatus);
  M5.Display.printf("loops:%lu\n", debugState.loopCount);
  M5.Display.printf("batches:%lu\n", debugState.batchesSent);
  M5.Display.printf("setVal:%lu\n", debugState.setValueCount);
  M5.Display.printf("subscr:%u\n", debugState.subscribedCount);
  M5.Display.printf("imuFail:%lu\n", debugState.imuFailures);
  if (debugState.staleWarned) {
    M5.Display.printf("STALE:%u\n", debugState.staleReadCount);
  }
  M5.Display.printf("conn:%d strm:%d\n", deviceConnected, streaming);
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s, ble_gap_conn_desc* desc) override {
    deviceConnected = true;
    streaming = true;  // auto-start: no START_STREAM command needed
    dummyStream = false;
    sampleIndexInBatch = 0;
    updateDisplayStatus("Verbunden");
    Serial.println("BLE: client connected, auto-starting stream");
  }
  void onDisconnect(NimBLEServer* s, ble_gap_conn_desc* desc) override {
    deviceConnected = false;
    streaming = false;
    updateDisplayStatus("Getrennt");
    // Restart advertising so the app can reconnect without a device reset.
    NimBLEDevice::startAdvertising();
  }
};

class ControlPointCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    std::string value = c->getValue();
    if (value.length() < 1) return;
    uint8_t command = static_cast<uint8_t>(value[0]);

    switch (command) {
      case 0x01:  // START_STREAM → real IMU data, deferred start
        streaming = false;  // don't start immediately!
        dummyStream = false;  // use real IMU, not dummy data
        streamStartDelay = millis() + STREAM_START_DELAY_MS;
        sampleIndexInBatch = 0;
        updateDisplayStatus("arming IMU...");
        break;
      case 0x02:  // STOP_STREAM
        streaming = false;
        streamStartDelay = 0;  // cancel any pending deferred start
        updateDisplayStatus("gestoppt");
        break;
      case 0x03: {  // REQUEST_BATTERY
        uint8_t percent = getBatteryPercent();
        batteryChar->setValue(&percent, 1);
        batteryChar->notify();
        break;
      }
      case 0x04:  // DEBUG: toggle dummy stream (no IMU)
        dummyStream = !dummyStream;
        updateDisplayStatus(dummyStream ? "dummy on" : "dummy off");
        Serial.printf("CMD: 0x04 received -> dummyStream=%d\n", dummyStream);
        if (dummyStream && !streaming) streaming = true;
        break;
      default:
        break;
    }
  }
};

void setupBle() {
  NimBLEDevice::init(DEVICE_NAME);
  // NimBLE handles MTU negotiation properly: set the server's max MTU so
  // the 52-byte payload fits without fragmentation. Bluedroid was the
  // root cause of the 1-batch streaming bug.
  NimBLEDevice::setMTU(517);
  server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService* service = server->createService(SERVICE_UUID);

  // Xiaomi/HyperOS requires READ alongside NOTIFY for the CCCD write to
  // succeed. Without READ, the GATT stack may silently reject the CCCD
  // descriptor write, leaving getSubscribedCount() at 0 forever.
  sensorDataChar = service->createCharacteristic(
      SENSOR_DATA_CHAR_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  controlPointChar = service->createCharacteristic(
      CONTROL_POINT_CHAR_UUID, NIMBLE_PROPERTY::WRITE);
  controlPointChar->setCallbacks(new ControlPointCallbacks());

  batteryChar = service->createCharacteristic(
      BATTERY_CHAR_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  NimBLEDevice::startAdvertising();
}

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  M5.Display.setTextSize(2);
  M5.Display.println("Gym Tracker");
  M5.Display.println("Bereit");

  // ---- Aggressive IMU initialization ----
  // M5StickC Plus2 uses BMI270. Some units need multiple begin() calls or
  // a longer settle time before the sensor returns valid (non-zero) data.
  // Without this, the app sees only resting gravity (~1.0g) because the
  // IMU I2C bus is not ready yet when loop() starts reading.
  Serial.begin(115200);
  delay(100);
  Serial.println("FlowRep firmware booted");

  // ---- I2C Bus Diagnostics (ADR-018) ----
  // M5StickC Plus2 normally uses BMI270 at 0x69, but some genuine units
  // ship with MPU6886 at 0x68 due to supply-chain variations. The I2C bus
  // also hosts the AXP2101 PMIC (0x34) and RTC (0x51).
  // A scan reveals hardware issues before we even try IMU init.
  //
  // IMPORTANT: M5.begin() initialises Wire internally, but some library
  // versions don't set up the TX buffer. An explicit Wire.begin() with
  // the correct pins (SDA=21, SCL=22) prevents the NULL TX buffer crash.
  Wire.begin(21, 22);
  delay(50);
  Serial.println("I2C bus scan:");
  int i2cDevices = 0;
  bool foundAt0x68 = false, foundAt0x69 = false;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  found device at 0x%02X", addr);
      i2cDevices++;
      if (addr == 0x68) { foundAt0x68 = true; Serial.print(" (MPU6886?)"); }
      if (addr == 0x69) { foundAt0x69 = true; Serial.print(" (BMI270?)"); }
      if (addr == 0x34) Serial.print(" (AXP2101 PMIC)");
      if (addr == 0x51) Serial.print(" (RTC)");
      Serial.println();
    }
  }
  Serial.printf("I2C scan: %d device(s) found\n", i2cDevices);

  // Probe MPU6886 at 0x68 (WHO_AM_I register 0x75 = 0x19)
  if (foundAt0x68) {
    Wire.beginTransmission(0x68);
    Wire.write(0x75);
    if (Wire.endTransmission(false) == 0) {
      Wire.requestFrom(0x68, 1);
      if (Wire.available()) {
        uint8_t chipId = Wire.read();
        Serial.printf("WHO_AM_I at 0x68: 0x%02X", chipId);
        if (chipId == 0x19) Serial.println(" (MPU6886 OK)");
        else Serial.println(" (UNKNOWN CHIP!)");
      }
    }
  }

  // Probe BMI270 at 0x69 (CHIP_ID register 0x00 = 0x24)
  if (foundAt0x69) {
    Wire.beginTransmission(0x69);
    Wire.write(0x00);
    if (Wire.endTransmission(false) == 0) {
      Wire.requestFrom(0x69, 1);
      if (Wire.available()) {
        uint8_t chipId = Wire.read();
        Serial.printf("WHO_AM_I at 0x69: 0x%02X", chipId);
        if (chipId == 0x24) Serial.println(" (BMI270 OK)");
        else Serial.println(" (UNKNOWN CHIP!)");
      }
    }
  }

  // M5.Imu (M5Unified) auto-detects the actual IMU chip at runtime, so no
  // extra warning is needed here. The diagnostic above is informational only.

  Serial.println("IMU init: attempting M5.Imu.begin()...");

  bool imuOk = false;
  for (int attempt = 0; attempt < 3; attempt++) {
    // Last attempt: try lower I2C speed (100kHz) in case BMI270 struggles
    // at the default 400kHz on this specific HW revision.
    if (attempt == 2) {
      Wire.setClock(100000);
      Serial.println("IMU init attempt 2: trying 100kHz I2C...");
    }
    M5.Imu.begin();
    delay(500);  // generous settle time for BMI270 power-up

    float tax, tay, taz, tgx, tgy, tgz;
    if (M5.Imu.getAccel(&tax, &tay, &taz) && M5.Imu.getGyro(&tgx, &tgy, &tgz)) {
      float mag = sqrtf(tax*tax + tay*tay + taz*taz);
      Serial.printf("IMU init attempt %d: ax=%.3f ay=%.3f az=%.3f mag=%.3f\n",
                    attempt, tax, tay, taz, mag);
      // Valid: magnitude should be roughly 0.8–1.2g at rest (gravity)
      if (mag > 0.5f && mag < 2.0f) {
        imuOk = true;
        Serial.println("IMU init: OK (valid gravity vector)");
        break;
      } else {
        Serial.printf("IMU init attempt %d: unexpected mag=%.3f, retrying...\n",
                      attempt, mag);
      }
    } else {
      Serial.printf("IMU init attempt %d: getAccel/getGyro returned false\n", attempt);
    }
  }

  if (!imuOk) {
    Serial.println("IMU init: ALL ATTEMPTS FAILED - IMU may be unresponsive!");
    M5.Display.println("IMU FAIL!");
  } else {
    M5.Display.println("IMU OK");
  }

  setupBle();

  // Set initial battery value so BLE read() returns something useful.
  uint8_t pct = getBatteryPercent();
  batteryChar->setValue(&pct, 1);
}

void loop() {
  M5.update();
  debugState.loopCount++;

  // Heartbeat / status refresh on screen every ~250 ms so we can see whether
  // loop() is still alive even when Serial is silent. All display rendering is
  // done here, never from BLE callbacks, to stay thread-safe.
  unsigned long now = millis();
  if (now - debugState.lastDisplayUpdate > 250 || debugState.needsRefresh) {
    debugState.lastDisplayUpdate = now;
    debugState.needsRefresh = false;
    // Update subscribedCount so we can see if the client has actually
    // written the CCCD (the #1 diagnostic for the BLE streaming bug).
    debugState.subscribedCount = sensorDataChar->getSubscribedCount();
    renderDisplay();
  }

  // ---- IMU Serial debug dump: always runs (~1 Hz), even without BLE ----
  // This lets us see live IMU values via Serial Monitor immediately after boot.
  if (millis() - debugState.lastSerialDump > 1000) {
    debugState.lastSerialDump = millis();
    float ax, ay, az, gx, gy, gz;
    if (M5.Imu.getAccel(&ax, &ay, &az) && M5.Imu.getGyro(&gx, &gy, &gz)) {
      float mag = sqrtf(ax*ax + ay*ay + az*az);
      Serial.printf("IMU: a=(%.3f,%.3f,%.3f) mag=%.3f  g=(%.1f,%.1f,%.1f)  %s\n",
                    ax, ay, az, mag, gx, gy, gz,
                    dummyStream ? "DUMMY" : "real");
    } else {
      Serial.println("IMU: read failed");
    }
  }    // Keep deferred start for compatibility but streaming is now auto-started
    // in onConnect. The START_STREAM (0x01) command is still handled for
    // re-sync (resets batch index, turns off dummy mode).
    if (!streaming && streamStartDelay > 0 && millis() > streamStartDelay) {
      streaming = true;
      streamStartDelay = 0;
      sampleIndexInBatch = 0;
      updateDisplayStatus("IMU stream");
    }

  if (!deviceConnected || !streaming) {
    delay(10);
    return;
  }

  // Debug path: send constant dummy data without touching the IMU.
  // Only call notify() if the client has actually subscribed (CCCD written).
  // NimBLE's notify() is a silent no-op when getSubscribedCount() == 0,
  // which was the root cause of the 2+ hour BLE streaming bug.
  if (dummyStream) {
    if (sampleIndexInBatch == 0) {
      currentBatch.timestamp = millis();
    }
    SensorSampleWire& sample = currentBatch.samples[sampleIndexInBatch];
    sample.ax = 100;
    sample.ay = 200;
    sample.az = 300;
    sample.gx = 10;
    sample.gy = 20;
    sample.gz = 30;
    sampleIndexInBatch++;
    if (sampleIndexInBatch >= SAMPLES_PER_BATCH) {
      sensorDataChar->setValue(
          reinterpret_cast<uint8_t*>(&currentBatch), sizeof(currentBatch));
      debugState.setValueCount++;
      // DIAG: log what we wrote so Serial confirms dummy mode
      static unsigned long lastDummyLog = 0;
      if (millis() - lastDummyLog > 1000) {
        lastDummyLog = millis();
        float dmag = sqrtf(0.100f*0.100f + 0.200f*0.200f + 0.300f*0.300f);
        Serial.printf("BLE: DUMMY batch sent (mag=%.3f) setVal=%lu\n", dmag, debugState.setValueCount);
      }
      if (sensorDataChar->getSubscribedCount() > 0) {
        sensorDataChar->notify();
        debugState.batchesSent++;
      }
      sampleIndexInBatch = 0;
    }
    delay(20);  // ~50 Hz
    return;
  }

  float ax, ay, az, gx, gy, gz;
  // bool-returning reads; a false return means the IMU is not ready.
  // We log the failure but do NOT stop the stream — a single I2C glitch
  // must not kill an entire workout session. If failures persist, the
  // imuFail counter on the display will make it visible.
  if (!M5.Imu.getAccel(&ax, &ay, &az) || !M5.Imu.getGyro(&gx, &gy, &gz)) {
    debugState.imuFailures++;
    delay(5);  // brief backoff before retry
    return;     // skip this sample, try again next loop iteration
  }

  // ---- Stale-data detection ----
  // If all 6 axes are identical to the last reading, the IMU's I2C may be
  // hung. Track consecutive identical reads and warn via Serial + display.
  if (ax == debugState.lastAx && ay == debugState.lastAy && az == debugState.lastAz &&
      gx == debugState.lastGx && gy == debugState.lastGy && gz == debugState.lastGz) {
    debugState.staleReadCount++;
    if (debugState.staleReadCount > 200 && !debugState.staleWarned) {
      debugState.staleWarned = true;
      debugState.needsRefresh = true;
      Serial.println("WARNING: IMU data STALE (>200 identical reads) - I2C hung?");
    }
  } else {
    debugState.staleReadCount = 0;
    debugState.staleWarned = false;
  }
  debugState.lastAx = ax; debugState.lastAy = ay; debugState.lastAz = az;
  debugState.lastGx = gx; debugState.lastGy = gy; debugState.lastGz = gz;

  if (sampleIndexInBatch == 0) {
    currentBatch.timestamp = millis();
  }

  SensorSampleWire& sample = currentBatch.samples[sampleIndexInBatch];
  sample.ax = static_cast<int16_t>(ax * 1000.0f);   // scale 0.001 -> g
  sample.ay = static_cast<int16_t>(ay * 1000.0f);
  sample.az = static_cast<int16_t>(az * 1000.0f);
  sample.gx = static_cast<int16_t>(gx * 100.0f);    // scale 0.01 -> deg/s
  sample.gy = static_cast<int16_t>(gy * 100.0f);
  sample.gz = static_cast<int16_t>(gz * 100.0f);

  sampleIndexInBatch++;

  if (sampleIndexInBatch >= SAMPLES_PER_BATCH) {
    // Update GATT value unconditionally so read() always returns fresh data,
    // regardless of subscription state. HyperOS blocks notification delivery
    // but read() works with Over-the-Air Read Requests when no CCCD is set.
    sensorDataChar->setValue(
        reinterpret_cast<uint8_t*>(&currentBatch), sizeof(currentBatch));
    debugState.setValueCount++;
    if (sensorDataChar->getSubscribedCount() > 0) {
      sensorDataChar->notify();
      debugState.batchesSent++;
    }
    sampleIndexInBatch = 0;
    delay(20);  // ~50 Hz pacing — matches SAMPLE_RATE_HZ
  }
}
