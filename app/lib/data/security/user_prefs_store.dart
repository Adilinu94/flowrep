import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lightweight UX preferences (non-health flags) across app restarts.
///
/// Uses [FlutterSecureStorage] for consistency with [CalibrationStore]
/// (no extra SharedPreferences dependency). Values are simple toggles,
/// not motion/health payloads.
class UserPrefsStore {
  UserPrefsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// After successful calibration wizard: auto-start counting (Audit QW-2).
  static const keyAutoArmAfterCalib = 'pref_auto_arm_after_calib';

  /// Default **on** (product: avoid silent 0-rep after calib).
  Future<bool> loadAutoArmAfterCalib({bool defaultValue = true}) async {
    final raw = await _storage.read(key: keyAutoArmAfterCalib);
    if (raw == null || raw.isEmpty) return defaultValue;
    final lower = raw.toLowerCase();
    if (lower == '0' || lower == 'false' || lower == 'off') return false;
    if (lower == '1' || lower == 'true' || lower == 'on') return true;
    return defaultValue;
  }

  Future<void> saveAutoArmAfterCalib(bool enabled) async {
    await _storage.write(
      key: keyAutoArmAfterCalib,
      value: enabled ? '1' : '0',
    );
  }
}
