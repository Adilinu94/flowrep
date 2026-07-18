import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/security/calibration_store.dart';
import '../../../domain/calibration_contract.dart';
import '../../../domain/workout_engine.dart' show SensorSample;

/// Guided Calibration 2.0 (Konzept-Dokument, Paket 4-9): fuehrt den Nutzer
/// durch die 5 Stufen (Ruhe, 1 Rep, 5 bekannte Reps, 3 langsame Reps,
/// Review) und speichert das Ergebnis als ExerciseProfile.
///
/// Nimmt den [controller] als Parameter entgegen (Dependency Injection) -
/// aktuell wird von home_screen.dart ein PlaceholderCalibrationController
/// uebergeben; sobald die echte Implementierung existiert, aendert sich
/// nur die Stelle, an der dieser Screen konstruiert wird.
class CalibrationWizardScreen extends StatefulWidget {
  const CalibrationWizardScreen({
    super.key,
    required this.controller,
    required this.samples,
    required this.exerciseId,
  });

  final CalibrationController controller;
  final Stream<SensorSample> samples;
  final String exerciseId;

  @override
  State<CalibrationWizardScreen> createState() =>
      _CalibrationWizardScreenState();
}

class _CalibrationWizardScreenState extends State<CalibrationWizardScreen> {
  late CalibrationStage _stage;
  StreamSubscription<CalibrationStage>? _stageSub;
  StreamSubscription<SensorSample>? _samplesSub;
  Timer? _uiRefreshTimer;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _stage = widget.controller.stage;
    _stageSub = widget.controller.stageStream.listen((s) {
      if (!mounted) return;
      setState(() => _stage = s);
    });
    _samplesSub = widget.samples.listen(widget.controller.onSample);
    // progress/repsCountedInCurrentStage aendern sich zwischen Stage-
    // Wechseln (innerhalb derselben Stage) - dafuer reicht kein alleiniger
    // stageStream-Listener, ein leichter periodischer Refresh genuegt.
    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stageSub?.cancel();
    _samplesSub?.cancel();
    _uiRefreshTimer?.cancel();
    widget.controller.dispose();
    super.dispose();
  }

  void _cancel() {
    widget.controller.cancel();
    Navigator.of(context).pop(false);
  }

  void _restart() {
    setState(() {
      _saveError = null;
      widget.controller.reset();
      _stage = widget.controller.stage;
    });
  }

  Future<void> _accept() async {
    final profile = widget.controller.result;
    if (profile == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await CalibrationStore().saveProfile(profile: profile);
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
    switch (_stage) {
      case CalibrationStage.restBaseline:
        return 'Ruhephase';
      case CalibrationStage.singleRepAxis:
        return 'Eine Wiederholung';
      case CalibrationStage.knownCountFit:
        return 'Bekannte Wiederholungen';
      case CalibrationStage.tempoCheck:
        return 'Langsame Wiederholungen';
      case CalibrationStage.review:
        return 'Ergebnis';
      case CalibrationStage.failed:
        return 'Kalibrierung fehlgeschlagen';
    }
  }

  String get _instruction {
    switch (_stage) {
      case CalibrationStage.restBaseline:
        return 'Halte den Arm RUHIG in der Startposition. '
            'Die App misst jetzt deine Ruheposition und den Rauschboden.';
      case CalibrationStage.singleRepAxis:
        return 'Mach EINE einzelne, gleichmaessige Bizeps-Curl-Wiederholung. '
            'Daraus bestimmt die App die Bewegungsachse.';
      case CalibrationStage.knownCountFit:
        final n = widget.controller.targetRepsForCurrentStage;
        return 'Mach jetzt genau $n Bizeps-Curls in deinem normalen Tempo. '
            'Die Anzahl muss stimmen - das ist der Kern der Kalibrierung.';
      case CalibrationStage.tempoCheck:
        final n = widget.controller.targetRepsForCurrentStage;
        return 'Mach $n bewusst LANGSAME Wiederholungen, damit die '
            'Kalibrierung auch bei anderem Tempo verlaesslich bleibt.';
      case CalibrationStage.review:
        return 'Pruefe das Ergebnis unten. Du kannst es uebernehmen oder '
            'die Kalibrierung neu starten.';
      case CalibrationStage.failed:
        return widget.controller.failureReason ??
            'Es gab ein Problem bei der Kalibrierung.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.controller.targetRepsForCurrentStage;
    final reps = widget.controller.repsCountedInCurrentStage;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _instruction,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              if (_stage != CalibrationStage.review &&
                  _stage != CalibrationStage.failed) ...[
                if (target > 0) ...[
                  Text(
                    '$reps / $target',
                    style: const TextStyle(
                        fontSize: 56, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                ],
                LinearProgressIndicator(value: widget.controller.progress),
              ],
              if (_stage == CalibrationStage.review) _buildReview(context),
              if (_stage == CalibrationStage.failed) _buildFailed(context),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildReview(BuildContext context) {
    final profile = widget.controller.result;
    if (profile == null) {
      return const Text('Kein Ergebnis verfuegbar.');
    }
    final good = !profile.needsRecalibration;
    return Column(
      children: [
        Icon(
          good ? Icons.check_circle : Icons.info,
          color: good ? Colors.green : Colors.orange,
          size: 56,
        ),
        const SizedBox(height: 12),
        Text(
          good
              ? 'Kalibrierung sieht gut aus.'
              : 'Kalibrierung gespeichert, aber mit niedriger Qualitaet - '
                  'eine Wiederholung wird empfohlen.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'theta=${profile.theta.toStringAsFixed(3)} '
            'signal=${profile.chosenSignal.name} '
            'quality=${profile.qualityScore.toStringAsFixed(2)}',
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

  Widget _buildFailed(BuildContext context) {
    return const Column(
      children: [
        Icon(Icons.error, color: Colors.red, size: 56),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final isActive = _stage != CalibrationStage.review &&
        _stage != CalibrationStage.failed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (isActive)
            TextButton(onPressed: _cancel, child: const Text('Abbrechen')),
          if (_stage == CalibrationStage.failed)
            FilledButton(
                onPressed: _restart, child: const Text('Erneut versuchen')),
          if (_stage == CalibrationStage.review) ...[
            TextButton(
                onPressed: _saving ? null : _restart,
                child: const Text('Neu starten')),
            FilledButton(
              onPressed: _saving ? null : _accept,
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
