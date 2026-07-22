/// JitterBuffer: Wandelt unregelmäßige BLE-Pakete in einen gleichmäßigen
/// 50-Hz-Datenstrom um.
///
/// BLE-Pakete kommen in Bursts (z.B. 3 Pakete auf einmal, dann 40ms Pause).
/// Der JitterBuffer sammelt Pakete und gibt sie in festen 20ms-Intervallen
/// (50 Hz) an die SignalChain weiter.
///
/// Latenz: bufferSize * tickInterval = 6 * 20ms = 120ms (akzeptabel für Rep-Counting).
///
/// Verwendung:
/// ```dart
/// final buffer = JitterBuffer(
///   onFrame: (frame) => signalChain.process(...),
/// );
/// buffer.start();
/// // Pro BLE-Paket:
/// buffer.add(timestampMs, gx, gy, gz);
/// // Bei Disconnect:
/// buffer.stop();
/// ```
library;

import 'dart:async';
import 'dart:collection';

/// Ein rohes IMU-Sample im Puffer.
class _BufferedSample {
  final int timestampMs;
  final double gx;
  final double gy;
  final double gz;

  const _BufferedSample(this.timestampMs, this.gx, this.gy, this.gz);
}

/// Wandelt unregelmäßige BLE-Pakete in einen gleichmäßigen 50-Hz-Strom um.
class JitterBuffer {
  /// Callback für jedes ausgegebene Frame.
  /// Parameter: (timestampMs, gx, gy, gz)
  final void Function(int timestampMs, double gx, double gy, double gz) onFrame;

  /// Puffergröße (Anzahl Samples). Größer = mehr Latenz, aber robuster.
  final int bufferSize;

  /// Ausgabeintervall in Millisekunden (20ms = 50 Hz).
  final int tickIntervalMs;

  final Queue<_BufferedSample> _queue = Queue<_BufferedSample>();
  Timer? _timer;
  int _droppedFrames = 0;
  int _outputFrames = 0;

  /// Erstellt den JitterBuffer.
  ///
  /// [onFrame]: Callback für jedes ausgegebene Frame.
  /// [bufferSize]: Maximale Puffergröße (Standard: 6 Samples = 120ms).
  /// [tickIntervalMs]: Ausgabeintervall (Standard: 20ms = 50 Hz).
  JitterBuffer({
    required this.onFrame,
    this.bufferSize = 6,
    this.tickIntervalMs = 20,
  });

  /// Startet die periodische Ausgabe.
  ///
  /// Idempotent: Mehrfaches Aufrufen startet nur einen Timer.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(Duration(milliseconds: tickIntervalMs), (_) => _tick());
  }

  /// Stoppt die periodische Ausgabe und leert den Puffer.
  ///
  /// Aufrufen bei: Disconnect, App-Pause, Session-Ende.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
  }

  /// Fügt ein BLE-Paket zum Puffer hinzu.
  ///
  /// [timestampMs]: Zeitstempel des Pakets in Millisekunden.
  /// [gx], [gy], [gz]: Roh-Gyrowerte in °/s.
  ///
  /// Bei vollem Puffer: ältestes Sample wird verworfen (Drop-Oldest-Strategie).
  void add(int timestampMs, double gx, double gy, double gz) {
    if (_queue.length >= bufferSize) {
      _queue.removeFirst();
      _droppedFrames++;
    }
    _queue.addLast(_BufferedSample(timestampMs, gx, gy, gz));
  }

  /// Interner Tick: Gibt ein Sample aus dem Puffer aus.
  void _tick() {
    if (_queue.isEmpty) return;

    final sample = _queue.removeFirst();
    _outputFrames++;
    onFrame(sample.timestampMs, sample.gx, sample.gy, sample.gz);
  }

  /// true, wenn der Timer läuft.
  bool get isRunning => _timer != null;

  /// Aktuelle Pufferfüllung (0 = leer, bufferSize = voll).
  int get queueLength => _queue.length;

  /// Anzahl verworfener Frames seit Erstellung/Reset.
  int get droppedFrames => _droppedFrames;

  /// Anzahl ausgegebener Frames seit Erstellung/Reset.
  int get outputFrames => _outputFrames;

  /// Setzt Zähler zurück und leert den Puffer.
  void reset() {
    _queue.clear();
    _droppedFrames = 0;
    _outputFrames = 0;
  }

  /// Gibt Ressourcen frei.
  void dispose() {
    stop();
  }
}
