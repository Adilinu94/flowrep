import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, SystemSound, SystemSoundType;
import 'package:vibration/vibration.dart';

import '../../../data/security/calibration_store.dart';
import '../../../domain/calibration_controller.dart';
import '../../../domain/workout_engine.dart' show SensorSample;

/// Guided Calibration 2.0 (Konzept-Dokument, Paket 4-9): fuehrt den Nutzer
/// durch die 5 Stufen von [CalibrationController] (rest/singleRep/knownSet/
/// slowSet/review) und speichert das Ergebnis als ExerciseProfile.
///
/// Interaktionsmodell (siehe calibration_controller.dart-Dokumentation):
/// Jede Sammel-Stufe startet mit einem Vorbereitungs-Countdown (Standard
/// 5 s, Samples werden verworfen). Danach Vibration + Aufzeichnung.
/// Abschluss per "Weiter" (controller.finishStage()). Bei nicht
/// bestandenem Qualitaets-Gate (rest/singleRep) wird die Stufe wiederholt.
class CalibrationWizardScreen extends StatefulWidget {
  const CalibrationWizardScreen({
    super.key,
    required this.samples,
    required this.exerciseId,
    required this.deviceId,
    /// Prepare countdown before samples are accepted. 0 = start immediately
    /// (widget tests). Production default is 5 seconds.
    this.prepareCountdownSeconds = 5,
  });

  final Stream<SensorSample> samples;
  final String exerciseId;
  final String deviceId;
  final int prepareCountdownSeconds;

  @override
  State<CalibrationWizardScreen> createState() =>
      _CalibrationWizardScreenState();
}

class _CalibrationWizardScreenState extends State<CalibrationWizardScreen> {
  late final CalibrationController _controller;
  StreamSubscription<SensorSample>? _samplesSub;
  Timer? _uiTimer;
  Timer? _prepareTimer;
  String? _gateFailMessage;
  CalibrationReviewData? _review;
  bool _saving = false;
  String? _saveError;
  final _correctKnownCtrl = TextEditingController();
  final _correctSlowCtrl = TextEditingController();

  /// false until the prepare countdown finishes for the current stage.
  bool _isRecording = false;
  bool _isPreparing = false;
  int _prepareSecondsLeft = 0;

  // Metronom-Fallback (Konzept §3 Stufe B, V2): "nach 2 Fehlversuchen in
  // Stufe B, Metronom anbieten". CalibrationController.start() setzt
  // JEDE Stufe zurueck - der Zaehler muss also hier im Screen-State
  // leben, nicht im Controller, um ueber mehrere Neustarts hinweg zu
  // zaehlen. Reiner Ton per SystemSound (kein Sprach-Fallback - laut
  // Konzept ist diese Entscheidung "erst in V2 noetig", Ton allein
  // braucht sie noch nicht), keine neue Dependency.
  int _knownSetFailureCount = 0;
  Timer? _metronomTimer;
  bool _metronomActive = false;
  static const _metronomIntervall = Duration(milliseconds: 1000); // 60 bpm

  @override
  void initState() {
    super.initState();
    _controller = CalibrationController(
      exerciseId: widget.exerciseId,
      onStageAdvanced: (stage) {
        if (!mounted) return;
        _metronomTimer?.cancel();
        setState(() {
          _gateFailMessage = null;
          _metronomActive = false;
        });
        if (_isCollectingStageFor(stage)) {
          _startPrepareCountdown();
        } else {
          _stopPrepare();
          setState(() {
            _isRecording = false;
            _isPreparing = false;
          });
        }
      },
      onQualityGateFail: (stage, reason) {
        if (!mounted) return;
        setState(() {
          _gateFailMessage = reason;
          if (stage == CalibrationStage.knownSet) {
            _knownSetFailureCount++;
          }
        });
        // Buffer was cleared → give another prepare window to settle.
        if (_controller.bufferedSampleCount == 0 &&
            _isCollectingStageFor(stage)) {
          _startPrepareCountdown();
        }
      },
      onReviewDataReady: (data) {
        if (!mounted) return;
        setState(() => _review = data);
      },
    );
    _controller.start();
    // Gate samples: only feed the controller while actively recording.
    _samplesSub = widget.samples.listen(_onSample);
    // bufferedSampleCount aendert sich zwischen Stage-Callbacks - ein
    // leichter periodischer Refresh haelt die Live-Anzeige aktuell.
    _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    // First stage (rest): onStageAdvanced from start() already started
    // the prepare countdown.
  }

  void _onSample(SensorSample sample) {
    if (!_isRecording || _isPreparing) return;
    _controller.onSample(sample);
  }

  void _stopPrepare() {
    _prepareTimer?.cancel();
    _prepareTimer = null;
  }

  void _startPrepareCountdown() {
    _stopPrepare();
    final total = widget.prepareCountdownSeconds;
    if (total <= 0) {
      // Tests / skip: begin recording immediately.
      unawaited(_beginRecording());
      return;
    }
    setState(() {
      _isPreparing = true;
      _isRecording = false;
      _prepareSecondsLeft = total;
    });
    _prepareTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_prepareSecondsLeft <= 1) {
        t.cancel();
        _prepareTimer = null;
        unawaited(_beginRecording());
      } else {
        setState(() => _prepareSecondsLeft -= 1);
      }
    });
  }

  Future<void> _beginRecording() async {
    if (!mounted) return;
    setState(() {
      _isPreparing = false;
      _isRecording = true;
      _prepareSecondsLeft = 0;
    });
    await _pulseStartRecording();
  }

  /// Short phone vibration when recording actually starts.
  Future<void> _pulseStartRecording() async {
    try {
      final has = await Vibration.hasVibrator();
      if (has == true) {
        await Vibration.vibrate(duration: 80);
        return;
      }
    } catch (_) {
      // Plugin unavailable (tests / desktop) — fall through.
    }
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  @override
  void dispose() {
    _samplesSub?.cancel();
    _uiTimer?.cancel();
    _prepareTimer?.cancel();
    _metronomTimer?.cancel();
    _correctKnownCtrl.dispose();
    _correctSlowCtrl.dispose();
    super.dispose();
  }

  void _toggleMetronom() {
    if (_metronomActive) {
      _metronomTimer?.cancel();
      setState(() => _metronomActive = false);
      return;
    }
    setState(() => _metronomActive = true);
    SystemSound.play(SystemSoundType.click);
    _metronomTimer = Timer.periodic(_metronomIntervall, (_) {
      SystemSound.play(SystemSoundType.click);
    });
  }

  void _cancel() => Navigator.of(context).pop(false);

  void _restart() {
    setState(() {
      _gateFailMessage = null;
      _review = null;
      _saveError = null;
    });
    _controller.start();
    // onStageAdvanced → prepare countdown for rest.
  }

  void _next() {
    if (!_isRecording || _isPreparing) return;
    _controller.finishStage();
  }

  void _correctKnown() {
    final n = int.tryParse(_correctKnownCtrl.text);
    if (n == null || n < 1) return;
    setState(() {
      _controller.userCorrectCount(CalibrationStage.knownSet, n);
    });
  }

  void _correctSlow() {
    final n = int.tryParse(_correctSlowCtrl.text);
    if (n == null || n < 1) return;
    setState(() {
      _controller.userCorrectCount(CalibrationStage.slowSet, n);
    });
  }

  Future<void> _accept() async {
    final review = _review;
    if (review == null || !review.ready) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final store = CalibrationStore();
      final previous = await store.loadProfile(
        exerciseId: widget.exerciseId,
        deviceId: widget.deviceId,
      );
      _controller.finishStage(); // review -> done
      final profile = _controller.finalize(previous: previous);
      if (profile == null) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _saveError = 'Kalibrierung unvollstaendig - bitte neu starten.';
        });
        return;
      }
      await store.saveProfile(profile: profile);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Speichern fehlgeschlagen: $e';
      });
    }
  }

  String get _title {
    switch (_controller.stage) {
      case CalibrationStage.rest:
        return 'Ruhephase';
      case CalibrationStage.singleRep:
        return 'Eine Wiederholung';
      case CalibrationStage.knownSet:
        return 'Bekannte Wiederholungen';
      case CalibrationStage.slowSet:
        return 'Langsame Wiederholungen';
      case CalibrationStage.review:
        return 'Ergebnis';
      case CalibrationStage.done:
        return 'Fertig';
      case CalibrationStage.failed:
        return 'Abgebrochen';
    }
  }

  String get _instruction {
    if (_isPreparing) {
      return 'Bereit machen: Position einnehmen und still halten. '
          'Aufzeichnung startet automatisch nach dem Countdown '
          '(Vibration = Start).';
    }
    switch (_controller.stage) {
      case CalibrationStage.rest:
        return 'Aufzeichnung läuft — Arm RUHIG halten (mind. 2 s). '
            'Warte bis die Anzeige grün ist, dann tippe auf Weiter. '
            'Tipp: M5 auf dem Oberschenkel ablegen.';
      case CalibrationStage.singleRep:
        return 'Mach EINE einzelne, gleichmaessige Bizeps-Curl-Wiederholung, '
            'dann tippe auf Weiter. Daraus bestimmt die App die Bewegungsachse.';
      case CalibrationStage.knownSet:
        final n = _controller.knownSetCount;
        return 'Mach genau $n Bizeps-Curls in deinem normalen Tempo, dann '
            'tippe auf Weiter. Die Anzahl muss stimmen - das ist der Kern '
            'der Kalibrierung.';
      case CalibrationStage.slowSet:
        final n = _controller.slowSetCount;
        return 'Mach $n bewusst LANGSAME Wiederholungen, dann tippe auf '
            'Weiter, damit die Kalibrierung auch bei anderem Tempo '
            'verlaesslich bleibt.';
      case CalibrationStage.review:
        return 'Pruefe das Ergebnis unten.';
      case CalibrationStage.done:
        return 'Kalibrierung abgeschlossen.';
      case CalibrationStage.failed:
        return 'Die Kalibrierung wurde abgebrochen.';
    }
  }

  bool _isCollectingStageFor(CalibrationStage stage) => const {
        CalibrationStage.rest,
        CalibrationStage.singleRep,
        CalibrationStage.knownSet,
        CalibrationStage.slowSet,
      }.contains(stage);

  bool get _isCollectingStage => _isCollectingStageFor(_controller.stage);

  /// Tap-to-Tag (Konzept §2.6/§3, V2) ist nur waehrend der beiden
  /// Reps-mit-bekannter-Anzahl-Stufen sinnvoll - in rest/singleRep gibt
  /// es keine "fertige Wiederholung" zum Markieren.
  bool get _tapButtonVisible =>
      _isRecording &&
      (_controller.stage == CalibrationStage.knownSet ||
          _controller.stage == CalibrationStage.slowSet);

  int get _tapCountForCurrentStage =>
      _controller.stage == CalibrationStage.knownSet
          ? _controller.tapCountB
          : _controller.tapCountC;

  @override
  Widget build(BuildContext context) {
    final seconds =
        _controller.bufferedSampleCount / _controller.sampleRateHz;
    return Scaffold(
      appBar: AppBar(title: Text(_title), automaticallyImplyLeading: false),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _instruction,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              if (_isCollectingStage && _isPreparing) ...[
                _buildPrepareCountdown(context),
              ],
              if (_isCollectingStage && _isRecording) ...[
                Text(
                  '${seconds.toStringAsFixed(1)} s aufgezeichnet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                if (_controller.stage == CalibrationStage.rest) ...[
                  const SizedBox(height: 16),
                  _buildRestGateLive(context),
                ],
                if (_gateFailMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _gateFailMessage!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
                if (_tapButtonVisible) ...[
                  const SizedBox(height: 20),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(_controller.addTap);
                    },
                    icon: const Icon(Icons.touch_app),
                    label: const Text('Tippe bei jeder fertigen Wiederholung'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_tapCountForCurrentStage Tap(s) erfasst - optional, '
                    'hilft der Kalibrierung',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_controller.stage == CalibrationStage.knownSet &&
                    _knownSetFailureCount >= 2) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade800,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Fällt es schwer, ein gleichmäßiges Tempo zu '
                          'halten? Ein Metronom kann helfen.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _toggleMetronom,
                          icon: Icon(
                            _metronomActive ? Icons.stop : Icons.music_note,
                          ),
                          label: Text(
                            _metronomActive
                                ? 'Metronom stoppen'
                                : 'Führe mich im Takt (60/min)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              // Gate-fail message during prepare (after failed attempt)
              if (_isCollectingStage &&
                  _isPreparing &&
                  _gateFailMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _gateFailMessage!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
              if (_controller.stage == CalibrationStage.review)
                _buildReview(context),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildPrepareCountdown(BuildContext context) {
    final total = widget.prepareCountdownSeconds;
    final progress =
        total > 0 ? (total - _prepareSecondsLeft) / total : 1.0;
    return Column(
      children: [
        Text(
          '$_prepareSecondsLeft',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Aufzeichnung startet in $_prepareSecondsLeft s…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Position einnehmen — noch nicht bewegen',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final review = _review;
    if (review == null || !review.ready) {
      return Column(
        children: [
          const Icon(Icons.info, color: Colors.orange, size: 48),
          const SizedBox(height: 8),
          Text(
            'Keine Parameter-Konfiguration hat exakt '
            '${_controller.knownSetCount}/${_controller.knownSetCount} '
            'gezaehlt. Bitte korrigiere unten die tatsaechliche Anzahl.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _buildCorrectionRow(
            label: 'Tatsaechliche Anzahl (Stufe B)',
            controller: _correctKnownCtrl,
            onSubmit: _correctKnown,
          ),
        ],
      );
    }
    return Column(
      children: [
        Icon(
          review.matches ? Icons.check_circle : Icons.info,
          color: review.matches ? Colors.green : Colors.orange,
          size: 48,
        ),
        const SizedBox(height: 8),
        Text('Stufe B: ${review.countedKnown} / ${review.knownCount} gezaehlt'),
        Text(
          'Stufe C: ${review.countedSlow ?? '-'} / ${review.slowCount} gezaehlt',
        ),
        const SizedBox(height: 12),
        if (!review.matches) ...[
          if (review.countedKnown != review.knownCount)
            _buildCorrectionRow(
              label: 'Tatsaechliche Anzahl (Stufe B)',
              controller: _correctKnownCtrl,
              onSubmit: _correctKnown,
            ),
          if (review.countedSlow != review.slowCount)
            _buildCorrectionRow(
              label: 'Tatsaechliche Anzahl (Stufe C)',
              controller: _correctSlowCtrl,
              onSubmit: _correctSlow,
            ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'signal=${review.signal?.name} theta=${review.theta?.toStringAsFixed(3)}',
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: Colors.cyanAccent,
            ),
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(
            _saveError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _buildCorrectionRow({
    required String label,
    required TextEditingController controller,
    required VoidCallback onSubmit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: label, isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onSubmit,
            child: const Text('Korrigieren'),
          ),
        ],
      ),
    );
  }

  Widget _buildRestGateLive(BuildContext context) {
    final live = _controller.liveRestGate;
    if (live == null) {
      return Text(
        'Warte auf Sensor-Daten…',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      );
    }
    final ok = live.ready;
    final color = ok ? Colors.green.shade700 : Colors.orange.shade800;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ok ? 'Ruhe OK — Weiter tippen' : 'Noch nicht ruhig genug',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '|gyro| ${live.gyroMagMean.toStringAsFixed(1)} °/s  ·  '
            'Rauschen ${live.sigmaAccel.toStringAsFixed(3)} g  ·  '
            '${live.seconds.toStringAsFixed(1)} s',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!live.minSecondsReached)
            Text(
              'Mindestens 2 s still halten…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final stage = _controller.stage;
    final canFinish = _isRecording && !_isPreparing;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (_isCollectingStage) ...[
            TextButton(onPressed: _cancel, child: const Text('Abbrechen')),
            FilledButton(
              onPressed: canFinish ? _next : null,
              child: Text(
                _isPreparing
                    ? 'Warte… ($_prepareSecondsLeft)'
                    : 'Weiter',
              ),
            ),
          ],
          if (stage == CalibrationStage.review) ...[
            TextButton(
              onPressed: _saving ? null : _restart,
              child: const Text('Neu starten'),
            ),
            FilledButton(
              onPressed: (_saving || _review == null || !_review!.ready)
                  ? null
                  : _accept,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Uebernehmen'),
            ),
          ],
        ],
      ),
    );
  }
}
