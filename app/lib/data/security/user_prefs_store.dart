import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/config/engine_constants.dart';
import '../../domain/exercises/exercise_targets.dart';

/// Snapshot of UX preferences loaded from secure storage.
class UserPrefsSnapshot {
  final bool autoArmAfterCalib;
  final bool haptic;
  final bool audio;
  final bool blindMode;
  final bool m5ButtonControl;
  final bool buttonHaptic;
  final bool buttonAudio;
  final int restDurationSeconds;
  final bool adaptiveRest;
  final bool vbtMetrics;
  final bool diagnoseOverlay;
  final bool ghostGate;
  final int ghostIdlePauseSeconds;
  final bool cameraEnabled;
  final Map<String, ExerciseTarget> exerciseTargets;

  const UserPrefsSnapshot({
    this.autoArmAfterCalib = true,
    this.haptic = true,
    this.audio = false,
    this.blindMode = false,
    this.m5ButtonControl = true,
    this.buttonHaptic = true,
    this.buttonAudio = true,
    this.restDurationSeconds = kDefaultRestDurationSeconds,
    this.adaptiveRest = true,
    this.vbtMetrics = true,
    this.diagnoseOverlay = false,
    this.ghostGate = true,
    this.ghostIdlePauseSeconds = 45,
    this.cameraEnabled = false,
    this.exerciseTargets = const {},
  });
}

/// Lightweight UX preferences (non-health flags) across app restarts.
///
/// Uses [FlutterSecureStorage] for consistency with [CalibrationStore]
/// (no extra SharedPreferences dependency). Values are simple toggles /
/// ints, not motion/health payloads.
class UserPrefsStore {
  UserPrefsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // --- Keys ---
  static const keyAutoArmAfterCalib = 'pref_auto_arm_after_calib';
  static const keyHaptic = 'pref_haptic';
  static const keyAudio = 'pref_audio';
  static const keyBlindMode = 'pref_blind_mode';
  static const keyM5ButtonControl = 'pref_m5_button_control';
  static const keyButtonHaptic = 'pref_button_haptic';
  static const keyButtonAudio = 'pref_button_audio';
  static const keyRestDurationSeconds = 'pref_rest_duration_s';
  static const keyAdaptiveRest = 'pref_adaptive_rest';
  static const keyVbtMetrics = 'pref_vbt_metrics';
  static const keyDiagnoseOverlay = 'pref_diagnose_overlay';
  static const keyGhostGate = 'pref_ghost_gate';
  static const keyGhostIdlePauseSeconds = 'pref_ghost_idle_pause_s';
  static const keyCameraEnabled = 'pref_camera_enabled';
  /// JSON map `{exerciseId: {sets, reps}}` for Doc 15 FR-B9 targets.
  static const keyExerciseTargets = 'pref_exercise_targets_v1';

  /// Load all known prefs (missing keys → product defaults).
  Future<UserPrefsSnapshot> loadAll() async {
    const defaults = UserPrefsSnapshot();
    return UserPrefsSnapshot(
      autoArmAfterCalib: await _loadBool(
        keyAutoArmAfterCalib,
        defaultValue: defaults.autoArmAfterCalib,
      ),
      haptic: await _loadBool(keyHaptic, defaultValue: defaults.haptic),
      audio: await _loadBool(keyAudio, defaultValue: defaults.audio),
      blindMode:
          await _loadBool(keyBlindMode, defaultValue: defaults.blindMode),
      m5ButtonControl: await _loadBool(
        keyM5ButtonControl,
        defaultValue: defaults.m5ButtonControl,
      ),
      buttonHaptic: await _loadBool(
        keyButtonHaptic,
        defaultValue: defaults.buttonHaptic,
      ),
      buttonAudio: await _loadBool(
        keyButtonAudio,
        defaultValue: defaults.buttonAudio,
      ),
      restDurationSeconds: await _loadInt(
        keyRestDurationSeconds,
        defaultValue: defaults.restDurationSeconds,
      ),
      adaptiveRest: await _loadBool(
        keyAdaptiveRest,
        defaultValue: defaults.adaptiveRest,
      ),
      vbtMetrics:
          await _loadBool(keyVbtMetrics, defaultValue: defaults.vbtMetrics),
      diagnoseOverlay: await _loadBool(
        keyDiagnoseOverlay,
        defaultValue: defaults.diagnoseOverlay,
      ),
      ghostGate:
          await _loadBool(keyGhostGate, defaultValue: defaults.ghostGate),
      ghostIdlePauseSeconds: await _loadInt(
        keyGhostIdlePauseSeconds,
        defaultValue: defaults.ghostIdlePauseSeconds,
      ),
      cameraEnabled: await _loadBool(
        keyCameraEnabled,
        defaultValue: defaults.cameraEnabled,
      ),
      exerciseTargets: await loadExerciseTargets(),
    );
  }

  Future<Map<String, ExerciseTarget>> loadExerciseTargets() async {
    final raw = await _storage.read(key: keyExerciseTargets);
    if (raw == null || raw.isEmpty) return const {};
    try {
      return ExerciseTargets.mapFromJson(jsonDecode(raw));
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveExerciseTargets(Map<String, ExerciseTarget> targets) async {
    if (targets.isEmpty) {
      await _storage.delete(key: keyExerciseTargets);
      return;
    }
    final jsonMap = {
      for (final e in targets.entries)
        e.key: {
          'sets': e.value.targetSets,
          'reps': e.value.targetReps,
        },
    };
    await _storage.write(key: keyExerciseTargets, value: jsonEncode(jsonMap));
  }

  // --- Individual writers (called from EngineNotifier setters) ---

  Future<void> saveAutoArmAfterCalib(bool enabled) =>
      _saveBool(keyAutoArmAfterCalib, enabled);

  Future<void> saveHaptic(bool enabled) => _saveBool(keyHaptic, enabled);

  Future<void> saveAudio(bool enabled) => _saveBool(keyAudio, enabled);

  Future<void> saveBlindMode(bool enabled) =>
      _saveBool(keyBlindMode, enabled);

  Future<void> saveM5ButtonControl(bool enabled) =>
      _saveBool(keyM5ButtonControl, enabled);

  Future<void> saveButtonHaptic(bool enabled) =>
      _saveBool(keyButtonHaptic, enabled);

  Future<void> saveButtonAudio(bool enabled) =>
      _saveBool(keyButtonAudio, enabled);

  Future<void> saveRestDurationSeconds(int seconds) =>
      _saveInt(keyRestDurationSeconds, seconds);

  Future<void> saveAdaptiveRest(bool enabled) =>
      _saveBool(keyAdaptiveRest, enabled);

  Future<void> saveVbtMetrics(bool enabled) =>
      _saveBool(keyVbtMetrics, enabled);

  Future<void> saveDiagnoseOverlay(bool enabled) =>
      _saveBool(keyDiagnoseOverlay, enabled);

  Future<void> saveGhostGate(bool enabled) =>
      _saveBool(keyGhostGate, enabled);

  Future<void> saveGhostIdlePauseSeconds(int seconds) =>
      _saveInt(keyGhostIdlePauseSeconds, seconds);

  Future<void> saveCameraEnabled(bool enabled) =>
      _saveBool(keyCameraEnabled, enabled);

  /// Backward-compatible single-key load (tests / call sites).
  Future<bool> loadAutoArmAfterCalib({bool defaultValue = true}) =>
      _loadBool(keyAutoArmAfterCalib, defaultValue: defaultValue);

  // --- Internals ---

  Future<bool> _loadBool(String key, {required bool defaultValue}) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return defaultValue;
    final lower = raw.toLowerCase();
    if (lower == '0' || lower == 'false' || lower == 'off') return false;
    if (lower == '1' || lower == 'true' || lower == 'on') return true;
    return defaultValue;
  }

  Future<void> _saveBool(String key, bool enabled) async {
    await _storage.write(key: key, value: enabled ? '1' : '0');
  }

  Future<int> _loadInt(String key, {required int defaultValue}) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return defaultValue;
    return int.tryParse(raw) ?? defaultValue;
  }

  Future<void> _saveInt(String key, int value) async {
    await _storage.write(key: key, value: value.toString());
  }
}
