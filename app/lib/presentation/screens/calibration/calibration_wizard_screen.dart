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
/// Ablauf je Sammel-Stufe:
/// 1. **Briefing** — kurze Aufgabe lesen, dann „Bereit“ tippen
/// 2. **Countdown** (Standard 5 s) — Samples werden verworfen
/// 3. **Aufzeichnung** — Vibration = Start; Abschluss per „Weiter“
///
/// Bei nicht bestandenem Qualitaets-Gate (rest/singleRep) erneut Briefing.
class CalibrationWizardScreen extends StatefulWidget {
  const CalibrationWizardScreen({
    super.key,
    required this.samples,
    required this.exerciseId,
    required this.deviceId,
    /// Prepare countdown after „Bereit“. 0 = skip briefing+countdown (tests).
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

  /// Read instructions; countdown has not started yet.
  bool _isBriefing = false;

  /// Countdown running; samples ignored.
  bool _isPreparing = false;

  /// Samples are accepted.
  bool _isRecording = false;

  int _prepareSecondsLeft = 0;

  int _knownSetFailureCount = 0;
  Timer? _metronomTimer;
  bool _metronomActive = false;
  static const _metronomIntervall = Duration(milliseconds: 1000);

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
          _enterBriefing();
        } else {
          _stopPrepare();
          setState(() {
            _isBriefing = false;
            _isPreparing = false;
            _isRecording = false;
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
        // Buffer cleared → back to briefing so user can re-read + re-arm.
        if (_controller.bufferedSampleCount == 0 &&
            _isCollectingStageFor(stage)) {
          _enterBriefing();
        }
      },
      onReviewDataReady: (data) {
        if (!mounted) return;
        setState(() => _review = data);
      },
    );
    _controller.start();
    _samplesSub = widget.samples.listen(_onSample);
    _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    // First stage: onStageAdvanced from start() already entered briefing.
  }

  void _onSample(SensorSample sample) {
    if (!_isRecording || _isPreparing || _isBriefing) return;
    _controller.onSample(sample);
  }

  void _stopPrepare() {
    _prepareTimer?.cancel();
    _prepareTimer = null;
  }

  /// Show short task text; user taps „Bereit“ when ready.
  void _enterBriefing() {
    _stopPrepare();
    if (widget.prepareCountdownSeconds <= 0) {
      // Widget tests: skip briefing + countdown.
      unawaited(_beginRecording());
      return;
    }
    setState(() {
      _isBriefing = true;
      _isPreparing = false;
      _isRecording = false;
      _prepareSecondsLeft = 0;
    });
  }

  void _onReadyPressed() {
    if (!_isBriefing) return;
    _startPrepareCountdown();
  }

  void _startPrepareCountdown() {
    _stopPrepare();
    final total = widget.prepareCountdownSeconds;
    if (total <= 0) {
      unawaited(_beginRecording());
      return;
    }
    setState(() {
      _isBriefing = false;
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
      _isBriefing = false;
      _isPreparing = false;
      _isRecording = true;
      _prepareSecondsLeft = 0;
    });
    await _pulseStartRecording();
  }

  Future<void> _pulseStartRecording() async {
    try {
      final has = await Vibration.hasVibrator();
      if (has == true) {
        await Vibration.vibrate(duration: 80);
        return;
      }
    } catch (_) {}
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
  }

  void _next() {
    if (!_isRecording || _isPreparing || _isBriefing) return;
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
      _controller.finishStage();
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
        return 'Schritt 1 · Ruhe';
      case CalibrationStage.singleRep:
        return 'Schritt 2 · Eine Wiederholung';
      case CalibrationStage.knownSet:
        return 'Schritt 3 · ${_controller.knownSetCount} Curls';
      case CalibrationStage.slowSet:
        return 'Schritt 4 · ${_controller.slowSetCount} langsam';
      case CalibrationStage.review:
        return 'Schritt 5 · Ergebnis';
      case CalibrationStage.done:
        return 'Fertig';
      case CalibrationStage.failed:
        return 'Abgebrochen';
    }
  }

  /// Short, stage-specific task (always visible in collecting stages).
  String get _actionNow {
    switch (_controller.stage) {
      case CalibrationStage.rest:
        return 'Arm still halten (Startposition), mind. 2 s';
      case CalibrationStage.singleRep:
        return 'Genau 1 Bizeps-Curl, dann Weiter';
      case CalibrationStage.knownSet:
        return 'Genau ${_controller.knownSetCount} Curls im normalen Tempo';
      case CalibrationStage.slowSet:
        return 'Genau ${_controller.slowSetCount} LANGSAME Curls';
      case CalibrationStage.review:
        return 'Ergebnis prüfen';
      case CalibrationStage.done:
        return 'Fertig';
      case CalibrationStage.failed:
        return 'Abgebrochen';
    }
  }

  /// One-line peek at the following step (null on last collecting / review).
  String? get _actionNext {
    switch (_controller.stage) {
      case CalibrationStage.rest:
        return 'Danach: 1 einzelne Curl';
      case CalibrationStage.singleRep:
        return 'Danach: ${_controller.knownSetCount} normale Curls';
      case CalibrationStage.knownSet:
        return 'Danach: ${_controller.slowSetCount} langsame Curls';
      case CalibrationStage.slowSet:
        return 'Danach: Ergebnis prüfen';
      default:
        return null;
    }
  }

  String get _phaseHint {
    if (_isBriefing) {
      return 'Lies die Aufgabe, nimm Position ein, tippe dann Bereit.';
    }
    if (_isPreparing) {
      return 'Countdown — noch nicht bewegen. Vibration = Start.';
    }
    if (_isRecording) {
      switch (_controller.stage) {
        case CalibrationStage.rest:
          return 'Aufzeichnung läuft. Warte auf Grün, dann Weiter.';
        default:
          return 'Aufzeichnung läuft. Danach Weiter tippen.';
      }
    }
    return '';
  }

  bool _isCollectingStageFor(CalibrationStage stage) => const {
        CalibrationStage.rest,
        CalibrationStage.singleRep,
        CalibrationStage.knownSet,
        CalibrationStage.slowSet,
      }.contains(stage);

  bool get _isCollectingStage => _isCollectingStageFor(_controller.stage);

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isCollectingStage) ...[
                _buildTaskCard(context),
                const SizedBox(height: 16),
                Text(
                  _phaseHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
              ],
              if (_isCollectingStage && _isBriefing) ...[
                _buildBriefing(context),
              ],
              if (_isCollectingStage && _isPreparing) ...[
                _buildPrepareCountdown(context),
              ],
              if (_isCollectingStage && _isRecording) ...[
                Text(
                  '${seconds.toStringAsFixed(1)} s aufgezeichnet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                if (_controller.stage == CalibrationStage.rest) ...[
                  const SizedBox(height: 16),
                  _buildRestGateLive(context),
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
                    '$_tapCountForCurrentStage Tap(s) erfasst — optional',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_controller.stage == CalibrationStage.knownSet &&
                    _knownSetFailureCount >= 2) ...[
                  const SizedBox(height: 20),
                  _buildMetronomBox(context),
                ],
              ],
              if (_gateFailMessage != null &&
                  _isCollectingStage &&
                  !_isRecording) ...[
                const SizedBox(height: 16),
                _buildGateFailBox(),
              ],
              if (_gateFailMessage != null && _isRecording) ...[
                const SizedBox(height: 16),
                _buildGateFailBox(),
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

  Widget _buildTaskCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = _actionNext;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'JETZT',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            _actionNow,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (next != null) ...[
            const SizedBox(height: 12),
            Text(
              next,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBriefing(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.front_hand_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Kein Sensor-Stream bis du bereit bist.\n'
          'Position einnehmen → Bereit tippen → 5 s Countdown → Vibration.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
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
          'Start in $_prepareSecondsLeft s…',
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
      ],
    );
  }

  Widget _buildGateFailBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade900,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _gateFailMessage!,
        style: const TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildMetronomBox(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade800,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text(
            'Tempo ungleichmäßig? Metronom kann helfen.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _toggleMetronom,
            icon: Icon(_metronomActive ? Icons.stop : Icons.music_note),
            label: Text(
              _metronomActive
                  ? 'Metronom stoppen'
                  : 'Führe mich im Takt (60/min)',
            ),
          ),
        ],
      ),
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
        textAlign: TextAlign.center,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (_isCollectingStage) ...[
            TextButton(onPressed: _cancel, child: const Text('Abbrechen')),
            if (_isBriefing)
              FilledButton(
                onPressed: _onReadyPressed,
                child: Text(
                  widget.prepareCountdownSeconds > 0
                      ? 'Bereit — ${widget.prepareCountdownSeconds}s'
                      : 'Bereit',
                ),
              )
            else if (_isPreparing)
              FilledButton(
                onPressed: null,
                child: Text('Warte… ($_prepareSecondsLeft)'),
              )
            else
              FilledButton(
                onPressed: _isRecording ? _next : null,
                child: const Text('Weiter'),
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
