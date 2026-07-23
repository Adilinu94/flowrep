/// Central constants for signal processing and engine (P2-6).
///
/// Magic numbers live here so they are documented and changeable in one place.
library;

/// Sample rate of the M5StickC Plus2 IMU (Hz).
const double kSampleRateHz = 50.0;

/// Butterworth bandpass lower cutoff (Hz).
const double kBandpassLowHz = 0.1;

/// Butterworth bandpass upper cutoff (Hz).
const double kBandpassHighHz = 5.0;

/// Butterworth settle samples (~3τ at 0.1Hz / 50Hz).
const int kSettledSamples = 250;

/// Gyro-gate: |gyro| below this (°/s) → rest (baseline update allowed).
const double kGyroRestThresholdDegPerSec = 15.0;

/// Minimum delta above baseline for peak detection.
const double kMinThresholdAboveBaseline = 0.10;

/// Default rest timer duration (seconds).
const int kDefaultRestDurationSeconds = 90;

/// Reconnection: max attempts.
const int kMaxReconnectAttempts = 10;

/// Reconnection: max backoff (seconds).
const int kMaxReconnectBackoffSeconds = 16;

/// JitterBuffer size (samples).
const int kJitterBufferSize = 6;

/// JitterBuffer output interval (ms) → 50 Hz.
const int kJitterBufferTickMs = 20;

/// Template matching default correlation threshold.
const double kTemplateCorrelationThreshold = 0.65;

/// Template length (samples, normalized).
const int kTemplateLength = 64;

/// Packet loss rate above which UI warns (P2-5).
const double kPacketLossWarnThreshold = 0.05;
