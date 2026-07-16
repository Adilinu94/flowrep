import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists calibration parameters across app restarts using encrypted
/// storage (Android Keystore / iOS Keychain — DSGVO-compliant per ADR-010).
///
/// This replaces raw SharedPreferences which are unencrypted and would
/// violate DSGVO for derived motion data (Art. 9). flutter_secure_storage
/// encrypts at the OS level and integrates with deleteAllUserData().
///
/// See docs/ARCHITECTURE_REVIEW_2026-07-12.md §3 and ADR-015.
class CalibrationStore {
  CalibrationStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPeakThreshold = 'calib_peak_threshold';
  static const _keyMinThreshold = 'calib_min_threshold_above_baseline';
  static const _keyBaseline = 'calib_baseline_level';
  static const _keyDeviceId = 'calib_device_id';

  /// Saves the calibration result for a device. Only the latest calibration
  /// is kept (V1: single device, single exercise).
  Future<void> save({
    required String deviceId,
    required double peakThreshold,
    required double minThresholdAboveBaseline,
    required double baselineLevel,
  }) async {
    await Future.wait([
      _storage.write(key: _keyDeviceId, value: deviceId),
      _storage.write(
          key: _keyPeakThreshold, value: peakThreshold.toString()),
      _storage.write(
          key: _keyMinThreshold, value: minThresholdAboveBaseline.toString()),
      _storage.write(
          key: _keyBaseline, value: baselineLevel.toString()),
    ]);
  }

  /// Loads the last saved calibration, or null if none exists or it belongs
  /// to a different device.
  Future<CalibrationData?> load({required String deviceId}) async {
    final savedDeviceId = await _storage.read(key: _keyDeviceId);
    if (savedDeviceId == null || savedDeviceId != deviceId) return null;

    final peakStr = await _storage.read(key: _keyPeakThreshold);
    final minStr = await _storage.read(key: _keyMinThreshold);
    final baselineStr = await _storage.read(key: _keyBaseline);

    if (peakStr == null || minStr == null || baselineStr == null) return null;

    return CalibrationData(
      deviceId: deviceId,
      peakThreshold: double.parse(peakStr),
      minThresholdAboveBaseline: double.parse(minStr),
      baselineLevel: double.parse(baselineStr),
    );
  }

  /// DSGVO: deletes all stored calibration data. Only removes
  /// calibration-specific keys — does NOT touch the database encryption
  /// key managed by [DatabaseKeyManager].
  Future<void> deleteAll() async {
    await Future.wait([
      _storage.delete(key: _keyDeviceId),
      _storage.delete(key: _keyPeakThreshold),
      _storage.delete(key: _keyMinThreshold),
      _storage.delete(key: _keyBaseline),
    ]);
  }
}

/// Immutable calibration result loaded from persistent storage.
class CalibrationData {
  final String deviceId;
  final double peakThreshold;
  final double minThresholdAboveBaseline;
  final double baselineLevel;

  const CalibrationData({
    required this.deviceId,
    required this.peakThreshold,
    required this.minThresholdAboveBaseline,
    required this.baselineLevel,
  });
}
