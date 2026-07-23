import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// Haptic/Audio Feedback Service (SPEC Phase 5.1).
///
/// Gibt Vibration + optionalen Sound bei erkannten Wiederholungen.
/// Wird vom EngineNotifier aufgerufen, wenn ein Rep gezählt wird.
class FeedbackService {
  FeedbackService({
    this.enableHaptic = true,
    this.enableAudio = false,
  });

  bool enableHaptic;
  bool enableAudio;

  /// Lazy: constructing AudioPlayer touches platform channels and breaks
  /// pure unit tests. Created only when audio is actually played.
  AudioPlayer? _audioPlayer;
  bool? _hasVibrator;

  /// Initialisiert den Vibrations-Support (async, einmalig aufrufen).
  Future<void> init() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
    } catch (_) {
      _hasVibrator = false;
    }
  }

  /// Feedback bei einer gezählten Wiederholung.
  ///
  /// [qualityScore] 0.0–1.0: beeinflusst Vibrationsstärke.
  Future<void> onRepCounted({double? qualityScore}) async {
    if (enableHaptic) {
      await _vibrate(qualityScore);
    }
    if (enableAudio) {
      await _playRepSound();
    }
  }

  /// Feedback bei Satzende.
  Future<void> onSetCompleted({required int repCount}) async {
    if (enableHaptic) {
      try {
        // Doppelte Vibration für Satzende
        await Vibration.vibrate(duration: 100);
        await Future.delayed(const Duration(milliseconds: 150));
        await Vibration.vibrate(duration: 200);
      } catch (_) {
        // Plugin missing in tests / unsupported platform.
      }
    }
  }

  Future<void> _vibrate(double? qualityScore) async {
    if (_hasVibrator != true) return;

    // Gute Qualität → kurze Vibration, schlechte → längere
    final duration = qualityScore != null
        ? (qualityScore >= 0.7 ? 50 : 100)
        : 50;
    try {
      await Vibration.vibrate(duration: duration);
    } catch (_) {}
  }

  Future<void> _playRepSound() async {
    try {
      _audioPlayer ??= AudioPlayer();
      // Kurzer Klick-Sound (System-Sound)
      await _audioPlayer!.play(
        AssetSource('sounds/rep_click.wav'),
        volume: 0.5,
      );
    } catch (_) {
      // Sound-Datei existiert möglicherweise noch nicht — kein Fehler.
    }
  }

  void dispose() {
    _audioPlayer?.dispose();
    _audioPlayer = null;
  }
}
