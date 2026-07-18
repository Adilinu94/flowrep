import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/providers/ble_sensor_provider.dart';
import '../../data/providers/sensor_provider.dart';
import '../../data/repositories/csv_session_recorder.dart';
import '../../data/security/calibration_store.dart';
import '../../domain/workout_engine.dart';
import 'calibration/calibration_wizard_screen.dart';

/// Phase 0/1 screen: connect button, status text, live rep counter.
/// Works with both MockSensorProvider and BleSensorProvider.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.sensorProvider});

  final ISensorProvider sensorProvider;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SensorConnectionState _connectionState = SensorConnectionState.disconnected;
  WorkoutState _workoutState = WorkoutState.idle;
  int _repsInCurrentSet = 0;
  int? _lastCompletedSetCount;
  int? _batteryPercent;
  String? _errorText;
  Timer? _refreshTimer;
  double? _calibratedThreshold;
  int _calibrationPeaksFound = 0;
  late final WorkoutEngine _engine;  // stable for the lifetime of this State — applyCalibration() updates it in place (race-condition fix, 2026-07-16)
  late final bool _isMock;
  final _calibrationStore = CalibrationStore();
  String? _bleDeviceId;
  StreamSubscription<dynamic>? _samplesSub;
  StreamSubscription<dynamic>? _eventsSub;

  // CSV-Aufnahmefunktion (Dokument 07/08). Eigener, unabhaengiger Listener
  // auf denselben Sample-Stream - siehe csv_session_recorder.dart.
  final _recorder = CsvSessionRecorder();
  StreamSubscription<dynamic>? _recorderSamplesSub;
  Timer? _recordingSampleCountTimer;
  bool _isRecording = false;
  int _recordedSampleCount = 0;
  File? _lastRecordingFile;

  void _bindEngine() {
    _samplesSub?.cancel();
    _eventsSub?.cancel();
    _recorderSamplesSub?.cancel();
    _samplesSub = widget.sensorProvider.samples.listen(_engine.processSample);
    _eventsSub = _engine.events.listen(_onEngineEvent);
    // Unabhaengig vom Engine-Listener oben - siehe csv_session_recorder.dart.
    _recorderSamplesSub = widget.sensorProvider.samples.listen(_recorder.onSample);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      _recordingSampleCountTimer?.cancel();
      _recordingSampleCountTimer = null;
      final file = await _recorder.stop(_engine.exerciseId);
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordedSampleCount = _recorder.sampleCount;
        _lastRecordingFile = file;
      });
    } else {
      _recorder.start();
      setState(() {
        _isRecording = true;
        _recordedSampleCount = 0;
        _lastRecordingFile = null;
      });
      _recordingSampleCountTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (!mounted) return;
        setState(() => _recordedSampleCount = _recorder.sampleCount);
      });
    }
  }

  Future<void> _shareLastRecording() async {
    final file = _lastRecordingFile;
    if (file == null) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'FlowRep-Aufnahme'),
    );
  }

  @override
  void initState() {
    super.initState();
    _isMock = widget.sensorProvider is MockSensorProvider;
    _engine = WorkoutEngine(exerciseId: 'bicep_curl');
    _bindEngine();

    // Load saved calibration if available (P0-3: persistence).
    _loadCalibration();

    widget.sensorProvider.connectionState.listen(
      (SensorConnectionState state) {
        if (!mounted) return;
        setState(() {
          _connectionState = state;
        if (state == SensorConnectionState.connected) {
          _errorText = null;
          if (!_isMock) {
            final provider = widget.sensorProvider as BleSensorProvider;
            _bleDeviceId = provider.remoteId;
            _loadCalibration();
          }
          _engine.handleReconnect();
          _refreshTimer?.cancel();
          _refreshTimer = Timer.periodic(
            const Duration(milliseconds: 500),
            (_) { if (mounted) setState(() {}); },
          );
        } else if (state == SensorConnectionState.disconnected) {
          _refreshTimer?.cancel();
          _engine.handleDisconnect();
        } else {
          _refreshTimer?.cancel();
        }
        });
        if (state == SensorConnectionState.connected) {
          _refreshBattery();
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _errorText = error.toString());
      },
    );

  }

  Future<void> _refreshBattery() async {
    try {
      final percent = await widget.sensorProvider.readBatteryPercent();
      if (!mounted) return;
      setState(() => _batteryPercent = percent);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Akku lesen fehlgeschlagen: $e');
    }
  }

  Future<void> _connect() async {
    setState(() => _errorText = null);
    try {
      await widget.sensorProvider.connect();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionState = SensorConnectionState.disconnected;
        _errorText = e.toString();
      });
    }
  }

  String get _statusText {
    switch (_connectionState) {
      case SensorConnectionState.disconnected:
        return 'Getrennt';
      case SensorConnectionState.connecting:
        return _isMock ? 'Verbinde (Mock) …' : 'Verbinde mit GymTracker …';
      case SensorConnectionState.connected:
        return _isMock ? 'Verbunden (Mock)' : 'Verbunden (BLE)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FlowRep')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_statusText, style: Theme.of(context).textTheme.titleLarge),
            if (_batteryPercent != null) ...[
              const SizedBox(height: 8),
              Text('Akku: $_batteryPercent%'),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_connectionState == SensorConnectionState.connected && !_isMock) ...[
              Builder(
                builder: (context) {
                  final provider = widget.sensorProvider as BleSensorProvider;
                  return Column(
                    children: [
                      Text('MTU: ${provider.lastNegotiatedMtu}'),
                      Text('Batches: ${provider.receivedBatches}'),
                      Text('Rate: ${provider.pollingRateHz.toStringAsFixed(1)} Hz'),
                      Text('Parse-Fehler: ${provider.parseErrors}'),
                      const SizedBox(height: 4),
                      // ENGINE DIAG: sample count, state, baseline
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'ENG: samples=${_engine.diagEngineSampleCount} '
                          'state=${_workoutState.name} '
                          'thresh=${_engine.peakThreshold.toStringAsFixed(3)} '
                          'base=${_engine.baselineLevel.toStringAsFixed(3)}',
                          style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: Colors.cyanAccent),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 24),
            if (_connectionState == SensorConnectionState.disconnected)
              ElevatedButton(
                onPressed: _connect,
                child: const Text('Gerät verbinden'),
              ),
            if (_connectionState == SensorConnectionState.connected) ...[
              Text(
                '$_repsInCurrentSet',
                style: const TextStyle(fontSize: 96, fontWeight: FontWeight.bold),
              ),
              Text('Zustand: ${_workoutState.name}'),
              if (_lastCompletedSetCount != null)
                Text('Letzter Satz: $_lastCompletedSetCount Wiederholungen'),
              const SizedBox(height: 24),
              if (_isMock)
                ElevatedButton(
                  onPressed: () => widget.sensorProvider.simulateRepetition(),
                  child: const Text('Wiederholung simulieren (Mock)'),
                ),
              if (!_isMock)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () => widget.sensorProvider.disconnect(),
                      child: const Text('Trennen'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        final provider =
                            widget.sensorProvider as BleSensorProvider;
                        provider.toggleDummyStream();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                      child: const Text('Dummy Stream', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              if (_connectionState == SensorConnectionState.connected && !_isMock) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _openCalibrationWizard,
                  icon: const Icon(Icons.tune),
                  label: const Text('Mit Assistent kalibrieren'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
              if (_calibratedThreshold != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Kalibriert: ${_calibratedThreshold!.toStringAsFixed(2)}g '
                  '($_calibrationPeaksFound Peaks)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (!kReleaseMode && !_isMock) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _toggleRecording,
                      icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
                      label: Text(_isRecording
                          ? 'Aufnahme stoppen ($_recordedSampleCount)'
                          : 'Aufnahme starten'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecording ? Colors.red : Colors.red.shade200,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (_lastRecordingFile != null) ...[
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _shareLastRecording,
                        icon: const Icon(Icons.share),
                        label: const Text('Teilen'),
                      ),
                    ],
                  ],
                ),
                if (_lastRecordingFile != null)
                  Text(
                    'Gespeichert: ${_lastRecordingFile!.path.split(Platform.pathSeparator).last}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadCalibration() async {
    if (_isMock) return;
    final provider = widget.sensorProvider as BleSensorProvider;
    final deviceId = provider.remoteId;
    if (deviceId == null) return;
    _bleDeviceId = deviceId;

    final data = await _calibrationStore.load(deviceId: deviceId);
    if (data != null && mounted) {
      setState(() {
        _calibratedThreshold = data.peakThreshold;
      });
      // Apply persisted calibration IN PLACE — do NOT dispose and recreate
      // the engine. Previously, disposing + recreating caused a race
      // condition: the _CalibrationDialog holds a reference to the engine
      // (passed as a constructor parameter), so if _loadCalibration()
      // completed after the dialog was shown, the dialog would call
      // startGuidedCalibration() on the OLD (disposed) engine — silently
      // doing nothing. Found during the E2E hardware test on 2026-07-16.
      // See WorkoutEngine.applyCalibration() for the full diagnosis.
      _engine.applyCalibration(
        peakThreshold: data.peakThreshold,
        minThresholdAboveBaseline: data.minThresholdAboveBaseline,
      );
    }
  }

  void _onEngineEvent(WorkoutEngineEvent event) {
    if (!mounted) return;
    _recorder.onEngineStateChanged(event.state);
    setState(() {
      _workoutState = event.state;
      _repsInCurrentSet = event.repsInCurrentSet;
      if (event.completedSet != null) {
        _lastCompletedSetCount = event.completedSet!.countedReps;
      }
      if (event.calibratedThreshold != null) {
        _calibratedThreshold = event.calibratedThreshold;
        _calibrationPeaksFound = _engine.calibrationPeaksFound;
        _saveCalibration();
      }
    });
  }

  Future<void> _saveCalibration() async {
    if (_bleDeviceId == null) return;
    await _calibrationStore.save(
      deviceId: _bleDeviceId!,
      peakThreshold: _engine.peakThreshold,
      minThresholdAboveBaseline: _engine.minThresholdAboveBaseline,
      baselineLevel: _engine.baselineLevel,
    );
  }

  // Absichtlich noch vorhanden, aber nicht mehr verdrahtet (siehe
  // _openCalibrationWizard unten) - erst entfernen, wenn Guided
  // Calibration 2.0 auf echter Hardware bestaetigt ist.
  // ignore: unused_element
  void _showCalibrationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: _CalibrationDialog(engine: _engine),
      ),
    );
  }

  // Guided Calibration 2.0 (Konzept-Dokument, Paket 4-9). Ersetzt den
  // Aufruf von _showCalibrationDialog() oben als Einstiegspunkt fuer den
  // "Mit Assistent kalibrieren"-Button. _showCalibrationDialog() und
  // _CalibrationDialog bleiben bewusst im Code (siehe deren Definition
  // unten) statt geloescht zu werden, bis die neue Kalibrierung 2.0 auf
  // echter Hardware end-to-end bestaetigt ist.
  Future<void> _openCalibrationWizard() async {
    final deviceId = _bleDeviceId;
    if (deviceId == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CalibrationWizardScreen(
          samples: widget.sensorProvider.samples,
          exerciseId: _engine.exerciseId,
          deviceId: deviceId,
        ),
      ),
    );
    if (saved == true) {
      // Reload so der Home-Screen den neuen Stand sieht.
      _loadCalibration();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _samplesSub?.cancel();
    _eventsSub?.cancel();
    _recorderSamplesSub?.cancel();
    _recordingSampleCountTimer?.cancel();
    _recorder.dispose();
    _engine.dispose();
    final provider = widget.sensorProvider;
    if (provider is BleSensorProvider) {
      provider.dispose();
    } else if (provider is MockSensorProvider) {
      provider.dispose();
    }
    super.dispose();
  }
}

/// Modal dialog for the guided calibration flow (event-based).
/// See docs/CALIBRATION_MODE_CONCEPT.md for the design rationale.
class _CalibrationDialog extends StatefulWidget {
  const _CalibrationDialog({required this.engine});
  final WorkoutEngine engine;

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  String _phase = 'ready'; // ready | rest | countdown | recording | done
  int _countdownSeconds = 5;
  double _progress = 0.0;
  int _liveRepCount = 0;
  Timer? _timer;
  StreamSubscription<WorkoutEngineEvent>? _eventsSub;

  @override
  void initState() {
    super.initState();
    _eventsSub = widget.engine.events.listen((event) {
      if (!mounted) return;
      if (event.calibrationProgress != null) {
        setState(() {
          _progress = event.calibrationProgress!;
          _liveRepCount = event.repsInCurrentSet;
        });
      }
      if (event.calibratedThreshold != null) {
        setState(() => _phase = 'done');
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }

  void _startRest() {
    setState(() {
      _phase = 'rest';
      _countdownSeconds = 3;
    });
    // Create the timer FIRST, then let the engine collect baseline
    // samples during the 3-second rest phase. startGuidedCalibration()
    // is deferred to _startRecording() so the engine doesn't count
    // peaks during the 8 seconds before the user sees "Mach 10 Curls!".
    // See docs/ANALYSE_EXTERNE_KI_2026-07-12.md Point D.
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdownSeconds--);
      if (_countdownSeconds <= 0) {
        t.cancel();
        _startCountdown();
      }
    });
  }

  void _startCountdown() {
    setState(() {
      _phase = 'countdown';
      _countdownSeconds = 5;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdownSeconds--);
      if (_countdownSeconds <= 0) {
        t.cancel();
        _startRecording();
      }
    });
  }

  void _startRecording() {
    setState(() => _phase = 'recording');
    // Start calibration NOW — after 3s rest + 5s countdown = 8s of
    // baseline settling. The EMA filter has converged, and the user
    // sees "Mach 10 Bizeps-Curls!" — no more false peaks from setup.
    widget.engine.startGuidedCalibration();
  }

  void _cancel() {
    // Engine may or may not be in guidedCalibration depending on phase.
    // Safe to call cancelCalibration() anytime — it's a no-op in idle.
    widget.engine.cancelCalibration();
    _timer?.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_titleText),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_bodyText, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (_phase == 'rest')
              Text(
                '$_countdownSeconds',
                style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
              ),
            if (_phase == 'countdown')
              Text(
                '$_countdownSeconds',
                style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
              ),
            if (_phase == 'recording') ...[
              Text(
                '$_liveRepCount / ${WorkoutEngine.calibrationTargetReps}',
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              const Text('Erkannte Wiederholungen'),
              const SizedBox(height: 12),
              // DIAGNOSTIC: raw CALIB data visible on UI (adb logcat broken on HyperOS)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DIAG: maxAccel=${widget.engine.diagMaxAccel.toStringAsFixed(3)}g '
                      'maxGyro=${widget.engine.diagMaxGyro.toStringAsFixed(1)}deg/s '
                      'signals=${widget.engine.calibrationSignalCount}',
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.greenAccent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'threshold=${widget.engine.peakThreshold.toStringAsFixed(3)}g '
                      'baseline=${widget.engine.baselineLevel.toStringAsFixed(3)}g',
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.greenAccent),
                    ),
                  ],
                ),
              ),
            ],
            if (_phase == 'done') ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 8),
              Text(
                'Schwellenwert: ${widget.engine.peakThreshold.toStringAsFixed(2)}g',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${widget.engine.calibrationPeaksFound} Peaks gefunden'),
              const SizedBox(height: 12),
              // DIAGNOSTIC: final CALIB values for documentation
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CALIB FINAL: maxAccel=${widget.engine.diagMaxAccel.toStringAsFixed(3)}g '
                      'maxGyro=${widget.engine.diagMaxGyro.toStringAsFixed(1)}deg/s '
                      'signals=${widget.engine.finalCalibrationSignalCount}',
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.greenAccent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'threshold=${widget.engine.peakThreshold.toStringAsFixed(3)}g '
                      'baseline=${widget.engine.baselineLevel.toStringAsFixed(3)}g',
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.greenAccent),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_phase == 'ready' || _phase == 'rest' || _phase == 'recording')
          TextButton(
            onPressed: _cancel,
            child: const Text('Abbrechen'),
          ),
        if (_phase == 'ready')
          FilledButton(
            onPressed: _startRest,
            child: const Text('Start'),
          ),
        if (_phase == 'done')
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fertig'),
          ),
      ],
    );
  }

  String get _titleText {
    switch (_phase) {
      case 'ready':
        return 'Kalibrierung';
      case 'rest':
        return 'Halte den Arm ruhig...';
      case 'countdown':
        return 'Mach dich bereit...';
      case 'recording':
        return 'Mach 10 Bizeps-Curls!';
      case 'done':
        return 'Fertig!';
      default:
        return '';
    }
  }

  String get _bodyText {
    switch (_phase) {
      case 'ready':
        return 'Befestige den Sensor am Handgelenk und nimm die '
            'Startposition ein. Drück dann auf Start.';
      case 'rest':
        return 'Halte den Arm RUHIG in der Startposition. '
            'Die App misst jetzt deine Ruheposition...';
      case 'countdown':
        return 'Geh in die Startposition...';
      case 'recording':
        return 'Mach jetzt 10 gleichmäßige Bizeps-Curls. '
            'Die App zeichnet deine Bewegungen auf.';
      case 'done':
        return 'Die Kalibrierung war erfolgreich! Der Schwellenwert '
            'wurde an deine Bewegungen angepasst.';
      default:
        return '';
    }
  }
}
