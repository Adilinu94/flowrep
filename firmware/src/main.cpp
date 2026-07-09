// FlowRep firmware - M5StickC Plus2
//
// NOT hardware-verified. Written in Claude.ai before the board physically
// arrived (see chat note on the commit that added this file). Treat as a
// careful first draft, not confirmed-working code. First real steps once
// hardware is available:
//   1. Flash this, confirm the display shows the ready text.
//   2. Confirm "GymTracker" appears in a BLE scan from the phone.
//   3. Confirm MTU negotiates to >= 55 bytes (see docs/protocol.yaml).
// Exact M5.Imu / M5.Display API calls should be checked against whatever
// M5StickCPlus2 library version actually installs - library APIs shift
// between versions and this could not be compiled/checked here.

#include <M5StickCPlus2.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

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

BLEServer* server = nullptr;
BLECharacteristic* sensorDataChar = nullptr;
BLECharacteristic* controlPointChar = nullptr;
BLECharacteristic* batteryChar = nullptr;

bool deviceConnected = false;
bool streaming = false;
SensorBatchWire currentBatch;
uint8_t sampleIndexInBatch = 0;
unsigned long lastSampleMicros = 0;
const unsigned long sampleIntervalMicros = 1000000UL / SAMPLE_RATE_HZ;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    deviceConnected = true;
    M5.Display.println("Verbunden");
  }
  void onDisconnect(BLEServer* s) override {
    deviceConnected = false;
    streaming = false;
    M5.Display.println("Getrennt");
    // Restart advertising so the app can reconnect without a device reset.
    s->getAdvertising()->start();
  }
};

class ControlPointCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    std::string value = c->getValue();
    if (value.length() < 1) return;
    uint8_t command = static_cast<uint8_t>(value[0]);

    switch (command) {
      case 0x01:  // START_STREAM
        streaming = true;
        sampleIndexInBatch = 0;
        break;
      case 0x02:  // STOP_STREAM
        streaming = false;
        // TODO once hardware available: transition towards Wake-on-Motion
        // light sleep here after the timeout described in
        // GYM_TRACKER_ARCHITEKTUR.md Abschnitt 5.2.3 - not implemented in
        // this first draft, deliberately left as a follow-up so the
        // core streaming path can be validated on real hardware first.
        break;
      case 0x03: {  // REQUEST_BATTERY
        uint8_t percent = M5.Power.getBatteryLevel();
        batteryChar->setValue(&percent, 1);
        batteryChar->notify();
        break;
      }
      default:
        break;
    }
  }
};

void setupBle() {
  BLEDevice::init(DEVICE_NAME);
  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService* service = server->createService(SERVICE_UUID);

  sensorDataChar = service->createCharacteristic(
      SENSOR_DATA_CHAR_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  sensorDataChar->addDescriptor(new BLE2902());

  controlPointChar = service->createCharacteristic(
      CONTROL_POINT_CHAR_UUID, BLECharacteristic::PROPERTY_WRITE);
  controlPointChar->setCallbacks(new ControlPointCallbacks());

  batteryChar = service->createCharacteristic(
      BATTERY_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  batteryChar->addDescriptor(new BLE2902());

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  M5.Display.setTextSize(2);
  M5.Display.println("Gym Tracker");
  M5.Display.println("Bereit");

  // NOTE: verify the exact IMU init call against the installed
  // M5StickCPlus2 library version - some versions require an explicit
  // M5.Imu.begin() beyond what M5.begin() already does.
  M5.Imu.begin();

  setupBle();
}

void loop() {
  M5.update();

  if (!deviceConnected || !streaming) {
    delay(10);
    return;
  }

  unsigned long now = micros();
  if (now - lastSampleMicros < sampleIntervalMicros) {
    return;  // busy-wait-free pacing towards ~50 Hz
  }
  lastSampleMicros = now;

  float ax, ay, az, gx, gy, gz;
  // NOTE: exact method names (getAccelData/getGyroData vs getAccel/getGyro)
  // vary by M5StickCPlus2 library version - verify once toolchain exists.
  M5.Imu.getAccelData(&ax, &ay, &az);
  M5.Imu.getGyroData(&gx, &gy, &gz);

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
    sensorDataChar->setValue(
        reinterpret_cast<uint8_t*>(&currentBatch), sizeof(currentBatch));
    sensorDataChar->notify();
    sampleIndexInBatch = 0;
  }
}
