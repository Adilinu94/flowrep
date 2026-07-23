import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;

import '../../../data/security/calibration_store.dart';
import '../../../domain/calibration_controller.dart';
import '../../../domain/workout_engine.dart' show SensorSample;

/// Guided Calibration 2.0 (Konzept-Dokument, Paket 4-9): fuehrt den Nutzer
/// durch die 5 Stufen von [CalibrationController] (rest/singleRep/knownSet/
/// slowSet/review) und speichert das Ergebnis als ExerciseProfile.
///
/// Interaktionsmodell (siehe calibration_controller.dart-Dokumentation):
/// Jede Sammel-Stufe wird durch einen "Weiter"-Tap des Nutzers beendet
/// (controller.finishStage()), NICHT automatisch nach einer festen Anzahl
/// Samples. Bei nicht bestandenem Qualitaets-Gate (rest/singleRep) bleibt
/// die Stufe aktiv und zeigt den Grund an; der Nutzer wiederholt die
/// Bewegung und tippt erneut auf "Weiter".
class CalibrationWizardScreen extends StatefulWidget {
  const CalibrationWizardScreen({
    super.key,
    required this.samples,
    required this.exerciseId,
    required this.deviceId,
  });

  final Stream<SensorSample> samples;
  final String exerciseId;
  final String deviceId;

  @override
  State<CalibrationWizardScreen> createState() =>
      _CalibrationWizardScreenState();
}

class _CalibrationWizardScreenState extends State<CalibrationWizardScreen> {
  late final CalibrationController _controller;
  StreamSubscription<SensorSample>? _samplesSub;
  Timer? _uiTimer;
  String? _gateFailMessage;
  CalibrationReviewData? _review;
  bool _saving = false;
  String? _saveError;
  final _correctKnownCtrl = TextEditingController();
  final _correctSlowCtrl = TextEditingController();

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
      },
      onQualityGateFail: (stage, reason) {
        if (!mounted) return;
        setState(() {
          _gateFailMessage = reason;
          if (stage == CalibrationStage.knownSet) {
            _knownSetFailureCount++;
          }
        });
      },
      onReviewDataReady: (data) {
        if (!mounted) return;
        setState(() => _review = data);
      },
    );
    _controller.start();
    _samplesSub = widget.samples.listen(_controller.onSample);
    // bufferedSampleCount aendert sich zwischen Stage-Callbacks - ein
    // leichter periodischer Refresh haelt die Live-Anzeige aktuell.
    _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _samplesSub?.cancel();
    _uiTimer?.cancel();
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
      _controller.start();
    });
  }

  void _next() => _controller.finishStage();

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
    switch (_controller.stage) {
      case CalibrationStage.rest:
        return 'Halte den Arm RUHIG in der Startposition (mind. 2 s). '
            'Warte bis die Anzeige grün ist, dann tippe auf Weiter. '
            'Tipp: M5 kurz auf dem Oberschenkel ablegen, nicht wackeln.';
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

  bool get _isCollectingStage => const {
        CalibrationStage.rest,
        CalibrationStage.singleRep,
        CalibrationStage.knownSet,
        CalibrationStage.slowSet,
      }.contains(_controller.stage);

  /// Tap-to-Tag (Konzept §2.6/§3, V2) ist nur waehrend der beiden
  /// Reps-mit-bekannter-Anzahl-Stufen sinnvoll - in rest/singleRep gibt
  /// es keine "fertige Wiederholung" zum Markieren.
  bool get _tapButtonVisible =>
      _controller.stage == CalibrationStage.knownSet ||
      _controller.stage == CalibrationStage.slowSet;

  int get _tapCountForCurrentStage => _controller.stage == CalibrationStage.knownSet
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
              if (_isCollectingStage) ...[
                Text('${seconds.toStringAsFixed(1)} s aufgezeichnet',
                    style: Theme.of(context).textTheme.titleMedium),
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
                    child: Text(_gateFailMessage!,
                        style: const TextStyle(color: Colors.white)),
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
                  Text('$_tapCountForCurrentStage Tap(s) erfasst - optional, '
                      'hilft der Kalibrierung',
                      style: Theme.of(context).textTheme.bodySmall),
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
                          icon: Icon(_metronomActive
                              ? Icons.stop
                              : Icons.music_note),
                          label: Text(_metronomActive
                              ? 'Metronom stoppen'
                              : 'Führe mich im Takt (60/min)'),
                        ),
                      ],
                    ),
                  ),
                ],
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
        Text('Stufe C: ${review.countedSlow ?? '-'} / ${review.slowCount} gezaehlt'),
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
                fontSize: 10, fontFamily: 'monospace', color: Colors.cyanAccent),
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(_saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
              onPressed: onSubmit, child: const Text('Korrigieren')),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (_isCollectingStage) ...[
            TextButton(onPressed: _cancel, child: const Text('Abbrechen')),
            FilledButton(onPressed: _next, child: const Text('Weiter')),
          ],
          if (stage == CalibrationStage.review) ...[
            TextButton(
                onPressed: _saving ? null : _restart,
                child: const Text('Neu starten')),
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
