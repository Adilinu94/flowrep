/// Adaptiver Peak-Detektor nach Pan-Tompkins-Prinzip.
///
/// Erkennt Peaks im geglätteten g_p-Signal (Hüllkurve) mittels:
/// - Adaptiver Schwelle: θ = NPK + factor * (SPK - NPK)
/// - Zustandsmaschine: idle → rising → falling → Peak bestätigt/verworfen
/// - Refractory-Zeit: verhindert Doppelzählung
/// - Prominenz-Filter: unterdrückt Rausch-Peaks
///
/// SPK = Signal-Peak-Level (EMA bestätigter Peaks)
/// NPK = Noise-Peak-Level (EMA verworfener Peaks)
library;

import '../models/processed_frame.dart';
import 'peak_event.dart';

/// Interne Zustände der Peak-Erkennung.
enum _DetectorState { idle, rising, falling }

/// Adaptiver Peak-Detektor für Rep-Erkennung.
///
/// Verwendung:
/// ```dart
/// final detector = PeakDetector(sampleRateHz: 50.0);
/// // Pro Frame:
/// final peak = detector.process(frame);
/// if (peak != null) { /* Rep erkannt */ }
/// ```
class PeakDetector {
  // === KONFIGURATION ===
  final double _sampleRateHz;
  /// Configured sample rate (Hz), used for refractory conversion.
  double get sampleRateHz => _sampleRateHz;
  final double _thresholdFactor; // 0.25: Anteil zwischen NPK und SPK
  final double _fallingRatio; // 0.5: unter θ*ratio → falling
  final int _fallingDebounce; // 4 Samples Debounce
  final int _refractorySamples; // Refractory in Samples
  final double _prominenceRatio; // 0.2: min. Prominenz = SPK * ratio

  // === ADAPTIVE SCHWELLE (Pan-Tompkins) ===
  double _spk; // Signal-Peak-Level
  double _npk; // Noise-Peak-Level

  // === ZUSTAND ===
  _DetectorState _state = _DetectorState.idle;
  double _currentMax = 0.0;
  double _currentMin = double.maxFinite;
  int _fallingCount = 0;
  final List<double> _window = [];
  int _sampleIndex = 0;
  int? _lastPeakSampleIndex; // null = noch kein Peak erkannt
  int _lastPeakDurationSamples = 0;
  double _lastPeakProminence = 0.0;

  /// Erstellt den Peak-Detektor.
  ///
  /// [sampleRateHz]: Abtastrate (Standard: 50.0).
  /// [initialSpk]: Initiales Signal-Peak-Level (aus Profil oder Default 100).
  /// [initialNpk]: Initiales Noise-Peak-Level (aus Profil oder Default 10).
  /// [thresholdFactor]: Position der Schwelle zwischen NPK und SPK (0.25).
  /// [fallingRatio]: Verhältnis für Falling-Edge-Erkennung (0.5).
  /// [fallingDebounce]: Debounce-Samples für Falling-Bestätigung (4).
  /// [refractorySeconds]: Minimale Zeit zwischen Peaks (0.5s).
  /// [prominenceRatio]: Min. Prominenz als Anteil von SPK (0.2).
  PeakDetector({
    double sampleRateHz = 50.0,
    double initialSpk = 100.0,
    double initialNpk = 10.0,
    double thresholdFactor = 0.25,
    double fallingRatio = 0.5,
    int fallingDebounce = 4,
    double refractorySeconds = 0.5,
    double prominenceRatio = 0.2,
  })  : _sampleRateHz = sampleRateHz,
        _spk = initialSpk,
        _npk = initialNpk,
        _thresholdFactor = thresholdFactor,
        _fallingRatio = fallingRatio,
        _fallingDebounce = fallingDebounce,
        _refractorySamples = (refractorySeconds * sampleRateHz).round(),
        _prominenceRatio = prominenceRatio;

  /// Aktuelle adaptive Schwelle θ = NPK + factor * (SPK - NPK).
  double get currentThreshold => _npk + _thresholdFactor * (_spk - _npk);

  /// Aktuelles Signal-Peak-Level.
  double get spk => _spk;

  /// Aktuelles Noise-Peak-Level.
  double get npk => _npk;

  /// Verarbeitet EIN Frame. Gibt [PeakEvent] zurück wenn Peak bestätigt.
  ///
  /// [frame]: Verarbeitetes Frame aus der SignalChain.
  /// Rückgabe: PeakEvent oder null (kein Peak).
  PeakEvent? process(ProcessedFrame frame) {
    _sampleIndex++;
    final value = frame.smoothedGp; // Signiertes geglättetes g_p als Eingabe

    // NaN-Schutz
    if (value.isNaN) return null;

    final theta = currentThreshold;

    switch (_state) {
      case _DetectorState.idle:
        // Warte auf Rising Edge
        if (value > theta && !_inRefractory()) {
          _state = _DetectorState.rising;
          _currentMax = value;
          _window
            ..clear()
            ..add(value);
        } else {
          // Tracke Minimum für Prominenz-Berechnung
          if (value < _currentMin) {
            _currentMin = value;
          }
        }

      case _DetectorState.rising:
        _window.add(value);
        if (value > _currentMax) {
          _currentMax = value;
          _fallingCount = 0;
        }
        // Prüfe Falling Edge
        if (value < theta * _fallingRatio) {
          _state = _DetectorState.falling;
          _fallingCount = 1;
        }

      case _DetectorState.falling:
        _window.add(value);
        if (value > _currentMax) {
          // Doch kein Falling — zurück zu Rising
          _state = _DetectorState.rising;
          _currentMax = value;
          _fallingCount = 0;
        } else {
          _fallingCount++;
          if (_fallingCount >= _fallingDebounce) {
            // Falling Edge bestätigt → Peak-Kandidat auswerten
            final result = _evaluatePeak(frame.timestampMs);
            _state = _DetectorState.idle;
            _currentMin = value;
            return result;
          }
        }
    }
    return null;
  }

  /// Wertet einen Peak-Kandidaten aus (Prominenz-Check + SPK/NPK-Update).
  PeakEvent? _evaluatePeak(int timestampMs) {
    final prominence = _currentMax - _currentMin;
    final minProminence = _spk * _prominenceRatio;

    if (prominence >= minProminence) {
      // Peak bestätigt → SPK aktualisieren (EMA α=0.125)
      _spk = 0.125 * _currentMax + 0.875 * _spk;
      _lastPeakSampleIndex = _sampleIndex;
      _lastPeakDurationSamples = _window.length;
      _lastPeakProminence = prominence;

      return PeakEvent(
        sampleIndex: _sampleIndex,
        timestampMs: timestampMs,
        peakValue: _currentMax,
        precedingValley: _currentMin,
        prominence: prominence,
        durationSamples: _window.length,
        window: List<double>.from(_window),
      );
    } else {
      // Peak verworfen → NPK aktualisieren (EMA α=0.125)
      _npk = 0.125 * _currentMax + 0.875 * _npk;
      return null;
    }
  }

  /// Refractory-Prüfung (sample-basiert, da JitterBuffer gleichmäßigen Takt liefert).
  bool _inRefractory() {
    final last = _lastPeakSampleIndex;
    if (last == null) return false; // Noch kein Peak → keine Refractory
    return (_sampleIndex - last) < _refractorySamples;
  }

  /// Setzt den Detektor-Zustand zurück (NICHT SPK/NPK!).
  ///
  /// SPK/NPK werden aus dem Profil geladen und überleben Session-Wechsel.
  void reset() {
    _state = _DetectorState.idle;
    _currentMax = 0.0;
    _currentMin = double.maxFinite;
    _fallingCount = 0;
    _window.clear();
    _sampleIndex = 0;
    _lastPeakSampleIndex = null;
  }

  /// Aktualisiert SPK/NPK (z.B. nach Kalibrierung oder aus Profil).
  void updateLevels({double? spk, double? npk}) {
    if (spk != null) _spk = spk;
    if (npk != null) _npk = npk;
  }

  /// Anzahl verarbeiteter Samples seit letztem Reset.
  int get sampleCount => _sampleIndex;

  /// Dauer des letzten bestätigten Peaks in Samples.
  int get lastPeakDurationSamples => _lastPeakDurationSamples;

  /// Prominenz des letzten bestätigten Peaks.
  double get lastPeakProminence => _lastPeakProminence;
}
