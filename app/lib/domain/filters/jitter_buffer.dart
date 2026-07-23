/// JitterBuffer: Wandelt unregelmäßige BLE-Pakete in einen gleichmäßigen
/// 50-Hz-Datenstrom um.
///
/// BLE-Pakete kommen in Bursts (z.B. 3 Pakete auf einmal, dann 40ms Pause).
/// Der JitterBuffer sammelt Pakete und gibt sie in festen 20ms-Intervallen
/// (50 Hz) an die SignalChain weiter.
///
/// Latenz: bufferSize * tickInterval = 6 * 20ms = 120ms (akzeptabel für Rep-Counting).
///
/// Generisch: Funktioniert mit jedem Typ T (SensorSample, Roh-Werte, etc.).
///
/// Verwendung:
/// ```dart
/// final buffer = JitterBuffer<SensorSample>(
///   onFrame: (sample) => _sampleController.add(sample),
/// );
/// buffer.start();
/// // Pro BLE-Paket:
/// buffer.addBatch(samples);
/// // Bei Disconnect:
/// buffer.stop();
/// ```
library;

import 'dart:async';
import 'dart:collection';

/// Wandelt unregelmäßige BLE-Pakete in einen gleichmäßigen 50-Hz-Strom um.
///
/// [T]: Typ der gepufferten Elemente (z.B. SensorSample).
class JitterBuffer<T> {
  /// Callback für jedes ausgegebene Element.
  final void Function(T item) onFrame;

  /// Puffergröße (Anzahl Elemente). Größer = mehr Latenz, aber robuster.
  final int bufferSize;

  /// Ausgabeintervall in Millisekunden (20ms = 50 Hz).
  final int tickIntervalMs;

  final Queue<T> _queue = Queue<T>();
  Timer? _timer;
  int _droppedFrames = 0;
  int _outputFrames = 0;
  int _underrunCount = 0;
  int _totalTicks = 0;

  /// Erstellt den JitterBuffer.
  ///
  /// [onFrame]: Callback für jedes ausgegebene Element.
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

  /// Fügt ein einzelnes Element zum Puffer hinzu.
  ///
  /// Bei vollem Puffer: ältestes Element wird verworfen (Drop-Oldest-Strategie).
  void add(T item) {
    if (_queue.length >= bufferSize) {
      _queue.removeFirst();
      _droppedFrames++;
    }
    _queue.addLast(item);
  }

  /// Fügt mehrere Elemente auf einmal hinzu (z.B. ein BLE-Batch).
  ///
  /// [items]: Liste von Elementen (z.B. List<SensorSample>).
  void addBatch(List<T> items) {
    for (final item in items) {
      add(item);
    }
  }

  /// Interner Tick: Gibt ein Element aus dem Puffer aus.
  void _tick() {
    _totalTicks++;
    if (_queue.isEmpty) {
      _underrunCount++;
      return;
    }

    final item = _queue.removeFirst();
    _outputFrames++;
    onFrame(item);
  }

  /// true, wenn der Timer läuft.
  bool get isRunning => _timer != null;

  /// Aktuelle Pufferfüllung (0 = leer, bufferSize = voll).
  int get queueLength => _queue.length;

  /// Anzahl verworfener Frames seit Erstellung/Reset.
  int get droppedFrames => _droppedFrames;

  /// Anzahl ausgegebener Frames seit Erstellung/Reset.
  int get outputFrames => _outputFrames;

  /// Anzahl Underruns (Tick ohne verfügbares Sample) seit Erstellung/Reset.
  ///
  /// Hohe Underrun-Rate deutet auf BLE-Paketverlust oder zu kleinen Puffer.
  /// Bei anhaltend hoher Rate (>10%) sollte ein Filter-Reset erwogen werden,
  /// da IIR-Koeffizienten 50 Hz annehmen.
  int get underrunCount => _underrunCount;

  /// Drop-Rate als Bruchteil (0.0–1.0): drops / (drops + output).
  ///
  /// >0.1 = kritisch (Filter-Reset oder Sample-Hold erwägen).
  double get dropRate {
    final total = _droppedFrames + _outputFrames;
    if (total == 0) return 0.0;
    return _droppedFrames / total;
  }

  /// Underrun-Rate als Bruchteil (0.0–1.0): underruns / totalTicks.
  double get underrunRate {
    if (_totalTicks == 0) return 0.0;
    return _underrunCount / _totalTicks;
  }

  /// Setzt Zähler zurück und leert den Puffer.
  void reset() {
    _queue.clear();
    _droppedFrames = 0;
    _outputFrames = 0;
    _underrunCount = 0;
    _totalTicks = 0;
  }

  /// Gibt Ressourcen frei.
  void dispose() {
    stop();
  }
}
