/// Guided Calibration 2.0 — Domänen-Service (Konzept 2.0, Paket 2:
/// docs/KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md, §3 Stufen 0/A/B/C/D,
/// §6 Paket 2). Reines Dart, kein Flutter-Import: vollständig testbar und
/// bewusst getrennt von der WorkoutEngine-State-Machine. Die Engine-Anbindung
/// (Delegation des Alt-Pfads) folgt in Paket 4.
///
/// Kernidee: Die Kalibrierung bekommt die Wahrheit als BEKANNTE ANZAHL
/// (1 Rep → 5 Reps → 3 langsame Reps) und optimiert ihre Zähl-Parameter so,
/// dass sie diese Wahrheit reproduziert — statt an der eigenen Detektion zu
/// raten (Root Causes K1–K4 des Konzepts). 1:1-Portierung der verifizierten
/// Python-Referenz tools/workout_engine_simulation.py (Known-Count-Suite,
/// 5/5 Personas grün, Paket 1, Commit d76ebbb). Algorithmus-Konstanten
/// (falling_ratio 0,5, falling_debounce 4, Refractory-Grid 0,35–0,75·T0,
/// Tempo-Sonde 3×, Deckel med_C − 2,5·σ_rel·med_C) sind dort begründet.
library;

import 'dart:math';

import 'package:flowrep/domain/models/exercise_profile.dart';
import 'package:flowrep/domain/workout_engine.dart' show SensorSample;

/// Stufen der Guided Calibration 2.0 (Konzept §3).
enum CalibrationStage {
  /// Stufe 0: Ruhe — Baseline, Rausch-Sigma, Gyro-Bias (+ Qualitäts-Gate).
  rest,

  /// Stufe A: genau 1 Rep — Rotationsachse via PCA (3×3), Rep-Dauer T0.
  singleRep,

  /// Stufe B: genau N Reps (Standard 5) — Known-Count-Sweep.
  knownSet,

  /// Stufe C: genau M langsame Reps (Standard 3) — Tempo-Robustheit.
  slowSet,

  /// Stufe D: Review — gezählt vs. bekannt; die Anzahl ist über
  /// [CalibrationController.userCorrectCount] korrigierbar (Re-Optimierung).
  review,

  /// Abgeschlossen — [CalibrationController.finalize] liefert das Profil.
  done,

  /// Abgebrochen (z. B. nach wiederholtem Gate-Fehler durch die UI).
  failed,
}

/// Eine erkannte Wiederholung auf einem Kandidaten-Signal (Stufe B/C).
class RepMark {
  /// Sample-Index innerhalb der Stufen-Aufzeichnung.
  final int sampleIndex;

  /// Signal-Höhe am Detektions-Maximum (Einheit des gewählten Signals).
  final double height;

  const RepMark(this.sampleIndex, this.height);
}

/// Daten für den Review-Screen (Stufe D): gezählt vs. bekannt, inkl. der
/// gewählten Signale und Detektions-Marker für die Signal-Visualisierung.
class CalibrationReviewData {
  /// false, wenn der Sweep keine Konfiguration fand — die UI soll dann die
  /// tatsächliche Anzahl abfragen (userCorrectCount) statt „Passt so".
  final bool ready;

  /// Vom Sweep gewähltes Zählsignal (null wenn nicht ready).
  final ChosenSignal? signal;

  /// Gelernte Schwelle (nach Stufe C), Einheit von [signal].
  final double? theta;

  /// Baseline des gewählten Signals (Median der Ruhe-Ränder, Stufe B).
  final double? baseline;

  /// Bekannte Anzahl Stufe B (vom Nutzer, korrigierbar).
  final int knownCount;

  /// Mit den gelernten Parametern gezählte Reps in Stufe B.
  final int? countedKnown;

  /// Bekannte Anzahl Stufe C (langsame Reps).
  final int slowCount;

  /// Mit den gelernten Parametern gezählte Reps in Stufe C.
  final int? countedSlow;

  /// Gewähltes Signal der Stufe B (für die Visualisierung).
  final List<double> signalB;

  /// Detektions-Marker auf [signalB].
  final List<RepMark> marksB;

  /// Gewähltes Signal der Stufe C (leer, wenn C nicht ausgewertet wurde).
  final List<double> signalC;

  /// Detektions-Marker auf [signalC].
  final List<RepMark> marksC;

  const CalibrationReviewData({
    required this.ready,
    this.signal,
    this.theta,
    this.baseline,
    required this.knownCount,
    this.countedKnown,
    required this.slowCount,
    this.countedSlow,
    this.signalB = const [],
    this.marksB = const [],
    this.signalC = const [],
    this.marksC = const [],
  });

  /// true, wenn beide Stufen exakt die bekannte Anzahl zählen.
  bool get matches => countedKnown == knownCount && countedSlow == slowCount;
}

/// Reiner Dart-Service für die Guided Calibration 2.0. Ablauf:
/// [start] → Samples via [onSample] einspeisen → [finishStage] am Ende jeder
/// Stufe → im [CalibrationStage.review] ggf. [userCorrectCount] →
/// [finalize] liefert das [ExerciseProfile] (optional gegen das
/// Vorgänger-Profil geblendet, Konzept §2.2).
class CalibrationController {
  CalibrationController({
    this.exerciseId = kDefaultExerciseId,
    this.sampleRateHz = 50.0,
    this.knownSetCount = 5,
    this.slowSetCount = 3,
    this.onStageAdvanced,
    this.onQualityGateFail,
    this.onReviewDataReady,
  });

  /// Übungs-Schlüssel des zu erstellenden Profils (V1: 'bicep_curl').
  final String exerciseId;

  /// Abtastrate der IMU in Hz (M5StickC Plus2 liefert ~50 Hz).
  final double sampleRateHz;

  /// Erwartete (vom Nutzer bekannte) Anzahl Reps in Stufe B.
  int knownSetCount;

  /// Erwartete Anzahl langsamer Reps in Stufe C.
  int slowSetCount;

  /// Wird nach jedem Stufen-Übergang aufgerufen.
  final void Function(CalibrationStage stage)? onStageAdvanced;

  /// Qualitäts-Gate gefallen. Bei rest/singleRep wird die Stufe wiederholt
  /// (Puffer verworfen); bei knownSet wird trotzdem weitergegangen und das
  /// Review (Stufe D) übernimmt die Korrektur.
  final void Function(CalibrationStage stage, String reason)?
      onQualityGateFail;

  /// Review-Daten stehen bereit (nach slowSet und nach jeder Korrektur).
  final void Function(CalibrationReviewData data)? onReviewDataReady;

  CalibrationStage _stage = CalibrationStage.rest;
  bool _running = false;

  final List<SensorSample> _bufRest = [];
  final List<SensorSample> _bufA = [];
  final List<SensorSample> _bufB = [];
  final List<SensorSample> _bufC = [];

  _RestStats? _rest;
  _AxisResult? _axis;
  Map<ChosenSignal, List<double>>? _signaleB;
  Map<ChosenSignal, List<double>>? _signaleC;
  Map<ChosenSignal, (double, double)>? _metaB;
  _SweepCfg? _cfg;
  double? _thetaFinal;
  double? _baselineChosen;
  bool _cOk = false;
  double _quality = 0.0;

  // Tap-to-Tag (Konzept §2.6/§3, V2): rohe Tap-Sample-Indizes je Stufe,
  // VOR Lag-Korrektur. Optional - Known-Count funktioniert unveraendert
  // ohne jeden Tap; siehe addTap() unten fuer die volle Begruendung.
  final List<int> _tapsB = [];
  final List<int> _tapsC = [];

  /// Aktuelle Stufe.
  CalibrationStage get stage => _stage;

  /// true zwischen [start] und done/failed.
  bool get isRunning => _running;

  /// Anzahl gesammelter Samples der aktuellen Sammel-Stufe (UI-Fortschritt).
  int get bufferedSampleCount => switch (_stage) {
        CalibrationStage.rest => _bufRest.length,
        CalibrationStage.singleRep => _bufA.length,
        CalibrationStage.knownSet => _bufB.length,
        CalibrationStage.slowSet => _bufC.length,
        _ => 0,
      };

  /// Diagnose: gelernte Rotationsachse (Einheitsvektor) nach Stufe A.
  List<double>? get learnedAxis => _axis?.achse;

  /// Diagnose: Rep-Dauer T0 aus Stufe A (Sekunden).
  double? get learnedT0 => _axis?.t0;

  /// Diagnose: Varianzanteil der PCA-Hauptkomponente (Achsen-Qualität).
  double? get axisVarianceShare => _axis?.varianzAnteil;

  /// Diagnose: ob Stufe C (Tempo-Robustheit) erfolgreich war.
  bool get cOk => _cOk;

  /// Diagnose: Anzahl bisher registrierter Taps in Stufe B (Tap-to-Tag).
  int get tapCountB => _tapsB.length;

  /// Diagnose: Anzahl bisher registrierter Taps in Stufe C (Tap-to-Tag).
  int get tapCountC => _tapsC.length;

  /// Startet eine neue Kalibrierung in Stufe 0 (verwirft alle Puffer).
  void start() {
    _stage = CalibrationStage.rest;
    _running = true;
    _bufRest.clear();
    _bufA.clear();
    _bufB.clear();
    _bufC.clear();
    _tapsB.clear();
    _tapsC.clear();
    _rest = null;
    _axis = null;
    _signaleB = null;
    _signaleC = null;
    _metaB = null;
    _cfg = null;
    _thetaFinal = null;
    _baselineChosen = null;
    _cOk = false;
    _quality = 0.0;
    onStageAdvanced?.call(_stage);
  }

  /// Speist ein IMU-Sample in die aktuelle Sammel-Stufe ein.
  void onSample(SensorSample sample) {
    if (!_running) return;
    switch (_stage) {
      case CalibrationStage.rest:
        _bufRest.add(sample);
      case CalibrationStage.singleRep:
        _bufA.add(sample);
      case CalibrationStage.knownSet:
        _bufB.add(sample);
      case CalibrationStage.slowSet:
        _bufC.add(sample);
      case CalibrationStage.review:
      case CalibrationStage.done:
      case CalibrationStage.failed:
        break;
    }
  }

  /// Tap-to-Tag (Konzept §2.6/§3, "jederzeit in B-D: Tap-Button pro
  /// fertiger Rep", V2). Registriert EINEN Tap zum aktuell letzten
  /// Sample der laufenden Stufe B/C - ein rein additives, optionales
  /// Signal: ruft niemand [addTap] auf, verhaelt sich Known-Count exakt
  /// wie zuvor (siehe [_tapsAligned]: leere Tap-Liste => keine
  /// zusaetzliche Pruefung). Kein Effekt in rest/singleRep/review/done/
  /// failed - der Tap-Button ist in der UI nur waehrend B/C sichtbar.
  ///
  /// Bewusst NICHT in dieser Aenderung: Feedback-Tap waehrend des
  /// LIVE-Trainings (nach der Kalibrierung) - das Konzept ordnet die
  /// Adaption daraus explizit V3 zu ("erst loggen, Adaption (V3) nach
  /// Auswertung der Logs"), hier geht es nur um die Kalibrierungs-Stufen
  /// selbst.
  void addTap() {
    if (!_running) return;
    switch (_stage) {
      case CalibrationStage.knownSet:
        if (_bufB.isNotEmpty) _tapsB.add(_bufB.length - 1);
      case CalibrationStage.slowSet:
        if (_bufC.isNotEmpty) _tapsC.add(_bufC.length - 1);
      case CalibrationStage.rest:
      case CalibrationStage.singleRep:
      case CalibrationStage.review:
      case CalibrationStage.done:
      case CalibrationStage.failed:
        break;
    }
  }

  /// Beendet die aktuelle Stufe und wertet ihren Puffer aus. Bei
  /// bestandenem Gate folgt der Übergang in die nächste Stufe.
  void finishStage() {
    if (!_running) return;
    switch (_stage) {
      case CalibrationStage.rest:
        _finishRest();
      case CalibrationStage.singleRep:
        _finishSingleRep();
      case CalibrationStage.knownSet:
        _finishKnownSet();
      case CalibrationStage.slowSet:
        _finishSlowSet();
      case CalibrationStage.review:
        _advance(CalibrationStage.done);
      case CalibrationStage.done:
      case CalibrationStage.failed:
        break;
    }
  }

  /// Stufe D: Der Nutzer korrigiert die tatsächlich ausgeführte Anzahl.
  /// Löst eine Re-Optimierung aus (Stufe B: kompletter Sweep mit neuer
  /// Anzahl; Stufe C: erneuter Tempo-Check). Nur im Review zulässig.
  /// Rückgabe: true, wenn danach eine valide Konfiguration vorliegt.
  bool userCorrectCount(CalibrationStage stage, int count) {
    if (count < 1 || _stage != CalibrationStage.review) return false;
    if (stage == CalibrationStage.knownSet) {
      knownSetCount = count;
      if (_bufB.isEmpty || _axis == null || _rest == null) return false;
      _runBSweep();
      if (_cfg != null && _bufC.isNotEmpty) _runC();
      onReviewDataReady?.call(reviewData);
      return _cfg != null;
    }
    if (stage == CalibrationStage.slowSet) {
      slowSetCount = count;
      if (_cfg == null || _bufC.isEmpty) return false;
      _runC();
      onReviewDataReady?.call(reviewData);
      return true;
    }
    return false;
  }

  /// Aktuelle Review-Daten (gezählt vs. bekannt, Signale + Marker).
  CalibrationReviewData get reviewData {
    if (_cfg == null || _thetaFinal == null) {
      return CalibrationReviewData(
        ready: false,
        knownCount: knownSetCount,
        slowCount: slowSetCount,
      );
    }
    final sigB = _signaleB![_cfg!.signal]!;
    final marksB = _zaehleEdge(sigB, sampleRateHz, _thetaFinal!,
        _cfg!.refractoryS, _baselineChosen!,
        prominenz: _cfg!.prominenz);
    var sigC = const <double>[];
    var marksC = const <RepMark>[];
    int? countedC;
    if (_signaleC != null && _bufC.isNotEmpty) {
      sigC = _signaleC![_cfg!.signal]!;
      marksC = _zaehleEdge(sigC, sampleRateHz, _thetaFinal!,
          _cfg!.refractoryS, _baselineChosen!,
          prominenz: _cfg!.prominenz);
      countedC = marksC.length;
    }
    return CalibrationReviewData(
      ready: true,
      signal: _cfg!.signal,
      theta: _thetaFinal,
      baseline: _baselineChosen,
      knownCount: knownSetCount,
      countedKnown: marksB.length,
      slowCount: slowSetCount,
      countedSlow: countedC,
      signalB: sigB,
      marksB: marksB,
      signalC: sigC,
      marksC: marksC,
    );
  }

  /// Baut das [ExerciseProfile] aus den gelernten Parametern. Liegt ein
  /// Vorgänger-Profil vor, wird geblendet (Konzept §2.2/§3 Stufe D):
  /// Gewicht der neuen Messung 0,5 bei guter Qualität (≥ 0,6), sonst 0,25 —
  /// eine schlechte Rekalibrierung kann das Profil nie ruinieren.
  /// Rückgabe null, wenn die Kalibrierung unvollständig ist.
  ExerciseProfile? finalize({ExerciseProfile? previous}) {
    if (_cfg == null || _thetaFinal == null || _axis == null ||
        _rest == null) {
      return null;
    }
    final sigB = _signaleB![_cfg!.signal]!;
    final marks = _zaehleEdge(sigB, sampleRateHz, _thetaFinal!,
        _cfg!.refractoryS, _baselineChosen!,
        prominenz: _cfg!.prominenz);
    final intervalle = <double>[
      for (var i = 1; i < marks.length; i++)
        (marks[i].sampleIndex - marks[i - 1].sampleIndex) / sampleRateHz,
    ];
    final medT = intervalle.isNotEmpty ? _median(intervalle) : _axis!.t0;
    final madT = intervalle.isNotEmpty
        ? _median([for (final v in intervalle) (v - medT).abs()])
        : 0.0;
    final neu = ExerciseProfile(
      exerciseId: exerciseId,
      rotationAxis: _axis!.achse,
      chosenSignal: _cfg!.signal,
      theta: _thetaFinal!,
      minRepIntervalSeconds: _cfg!.refractoryS,
      prominenceMin: _cfg!.prominenz,
      medianTSeconds: medT,
      madTSeconds: madT,
      gyroBias: _rest!.gyroBias,
      qualityScore: _quality,
      calibratedAt: DateTime.now(),
    );
    if (previous == null) return neu;
    final w = neu.qualityScore >= 0.6 ? 0.5 : 0.25;
    return previous.blendWith(neu, w);
  }

  // ---------------------------------------------------------------------
  // Stufen-Auswertung
  // ---------------------------------------------------------------------

  void _advance(CalibrationStage next) {
    _stage = next;
    onStageAdvanced?.call(next);
  }

  void _finishRest() {
    final stats = _restStats(_bufRest);
    if (!stats.gateOk) {
      _bufRest.clear();
      onQualityGateFail?.call(
        CalibrationStage.rest,
        'Ruhe-Gate nicht bestanden: |gyro|-Mittel '
        '${stats.gyroMagMean.toStringAsFixed(1)} °/s (Grenze 15), '
        'Accel-Sigma ${stats.sigmaAccel.toStringAsFixed(3)} g '
        '(Grenze 0,05), ${stats.n} Samples. Gerät stillhalten, Stufe '
        'wird wiederholt.',
      );
      return;
    }
    _rest = stats;
    _advance(CalibrationStage.singleRep);
  }

  void _finishSingleRep() {
    final res = _axisAnalysis(_bufA, _rest!);
    if (res == null) {
      _bufA.clear();
      onQualityGateFail?.call(
        CalibrationStage.singleRep,
        'Kein Bewegungsfenster gefunden (mindestens 5 Samples über der '
        'Aktivitäts-Schwelle nötig). Bitte genau 1 deutliche Wiederholung '
        'ausführen.',
      );
      return;
    }
    _axis = res;
    _advance(CalibrationStage.knownSet);
  }

  void _runBSweep() {
    _signaleB = _kandidatenSignale(_bufB, _axis!.achse, _rest!.gyroBias);
    _metaB = _signalMeta(_signaleB!);
    // Tap-to-Tag (Konzept §2.6, V2): rohe Taps auf ihr naechstes
    // Signal-Landmark (lokales gyroMag-Minimum) ausgerichtet, dann EIN
    // gemeinsamer Median-Lag ueber alle Taps abgezogen - nicht pro Tap
    // einzeln, siehe _lagKorrigierteTaps. gyroMag statt eines
    // Kandidaten-Signals, weil hier noch nicht feststeht, welches Signal
    // der Sweep gleich waehlt.
    final tapsKorrigiert =
        _lagKorrigierteTaps(_tapsB, _signaleB![ChosenSignal.gyroMag]!);
    _cfg = _knownCountSweep(
        _signaleB!, _metaB!, _axis!.t0, knownSetCount, tapsKorrigiert);
    if (_cfg != null) {
      // Finale Schwelle = median − k·MAD der validierten Peak-Höhen
      // (reproduziert die Sweep-Höhe; Referenz median_minus_k_mad).
      final (theta, _, _, _) = _medianMinusKMad(_cfg!.peakHoehen, _cfg!.theta);
      _cfg!.theta = theta;
      _baselineChosen = _metaB![_cfg!.signal]!.$1;
      _thetaFinal = theta;
      _quality = 1.0 - min(1.0, _cfg!.cv);
    } else {
      _thetaFinal = null;
      _baselineChosen = null;
      _quality = 0.0;
    }
  }

  void _finishKnownSet() {
    _runBSweep();
    if (_cfg == null) {
      onQualityGateFail?.call(
        CalibrationStage.knownSet,
        'Keine Parameter-Konfiguration zählt exakt '
        '$knownSetCount/$knownSetCount. Stufe C wird trotzdem '
        'aufgezeichnet; im Review (Stufe D) kann die tatsächliche Anzahl '
        'korrigiert werden.',
      );
    }
    _advance(CalibrationStage.slowSet);
  }

  void _runC() {
    if (_cfg == null || _signaleB == null) {
      _cOk = false;
      return;
    }
    _signaleC = _kandidatenSignale(_bufC, _axis!.achse, _rest!.gyroBias);
    final res = _stufeC(
      _signaleB![_cfg!.signal]!,
      _signaleC![_cfg!.signal]!,
      _baselineChosen!,
      _cfg!,
      knownSetCount,
      slowSetCount,
    );
    _cOk = res.ok;
    if (res.ok) _thetaFinal = res.theta;
  }

  void _finishSlowSet() {
    _runC();
    _advance(CalibrationStage.review);
    onReviewDataReady?.call(reviewData);
  }

  // ---------------------------------------------------------------------
  // Stufe 0: Ruheanalyse (Referenz stufe0_ruheanalyse)
  // ---------------------------------------------------------------------

  _RestStats _restStats(List<SensorSample> buf) {
    final n = buf.length;
    if (n == 0) {
      return const _RestStats(
        n: 0,
        baseline: 0.0,
        sigmaAccel: double.infinity,
        gyroBias: [0.0, 0.0, 0.0],
        sigmaGyro: double.infinity,
        gyroMagMean: double.infinity,
        gateOk: false,
      );
    }
    final accelMag = [for (final s in buf) s.accelMagnitude];
    final bias = [
      _mean([for (final s in buf) s.gx]),
      _mean([for (final s in buf) s.gy]),
      _mean([for (final s in buf) s.gz]),
    ];
    final gyroMag = [
      for (final s in buf)
        sqrt((s.gx - bias[0]) * (s.gx - bias[0]) +
            (s.gy - bias[1]) * (s.gy - bias[1]) +
            (s.gz - bias[2]) * (s.gz - bias[2]))
    ];
    final sigmaAccel = _std(accelMag);
    final gyroMagMean = _mean(gyroMag);
    final gateOk = gyroMagMean < 15.0 && sigmaAccel < 0.05;
    return _RestStats(
      n: n,
      baseline: _mean(accelMag),
      sigmaAccel: sigmaAccel,
      gyroBias: bias,
      sigmaGyro: _std(gyroMag),
      gyroMagMean: gyroMagMean,
      gateOk: gateOk,
    );
  }

  // ---------------------------------------------------------------------
  // Stufe A: Achsenanalyse via PCA 3×3 (Referenz stufeA_achsenanalyse)
  // ---------------------------------------------------------------------

  _AxisResult? _axisAnalysis(List<SensorSample> buf, _RestStats ruhe) {
    final bias = ruhe.gyroBias;
    final gyroZ = [
      for (final s in buf) [s.gx - bias[0], s.gy - bias[1], s.gz - bias[2]]
    ];
    final gyroMag = [
      for (final r in gyroZ) sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2])
    ];
    final schwelle = max(15.0, 4.0 * ruhe.sigmaGyro);
    final aktiv = [
      for (var i = 0; i < gyroMag.length; i++)
        if (gyroMag[i] > schwelle) i
    ];
    if (aktiv.length < 5) return null;
    final i0 = aktiv.first;
    final i1 = aktiv.last;
    final fenster = gyroZ.sublist(i0, i1 + 1);

    // 3×3-Kovarianz des Bias-korrigierten Fensters.
    final m = [0.0, 0.0, 0.0];
    for (final r in fenster) {
      m[0] += r[0];
      m[1] += r[1];
      m[2] += r[2];
    }
    m[0] /= fenster.length;
    m[1] /= fenster.length;
    m[2] /= fenster.length;
    final cov = List.generate(3, (_) => List.filled(3, 0.0));
    for (final r in fenster) {
      final d = [r[0] - m[0], r[1] - m[1], r[2] - m[2]];
      for (var k = 0; k < 3; k++) {
        for (var l = 0; l < 3; l++) {
          cov[k][l] += d[k] * d[l];
        }
      }
    }
    final denom = max(fenster.length - 1, 1);
    for (var k = 0; k < 3; k++) {
      for (var l = 0; l < 3; l++) {
        cov[k][l] /= denom;
      }
    }

    // Hauptkomponente via Jacobi-Eigenzerlegung (kein Package nötig —
    // Konzept „Neue Dependencies": 3D-Gyro braucht nur 3×3).
    final eig = _jacobiEigen3(cov);
    var imax = 0;
    for (var k = 1; k < 3; k++) {
      if (eig.w[k] > eig.w[imax]) imax = k;
    }
    var achse = [eig.v[0][imax], eig.v[1][imax], eig.v[2][imax]];
    var gPf = [
      for (final r in fenster)
        r[0] * achse[0] + r[1] * achse[1] + r[2] * achse[2]
    ];
    // Vorzeichen-Konvention: größter Ausschlag der Rep soll positiv sein.
    final mx = gPf.reduce(max);
    final mn = gPf.reduce(min);
    if (mx < -mn) {
      achse = [-achse[0], -achse[1], -achse[2]];
      gPf = [for (final v in gPf) -v];
    }
    final varSum = eig.w.fold<double>(0.0, (a, b) => a + b);
    return _AxisResult(
      achse: achse,
      t0: (i1 - i0) / sampleRateHz,
      i0: i0,
      i1: i1,
      gyroPeakFenster: gPf.reduce(max),
      varianzAnteil: varSum > 0 ? eig.w[imax] / varSum : 0.0,
    );
  }

  // ---------------------------------------------------------------------
  // Stufe B: Kandidaten-Signale + Known-Count-Sweep
  // (Referenz kandidaten_signale / known_count_sweep)
  // ---------------------------------------------------------------------

  Map<ChosenSignal, List<double>> _kandidatenSignale(
      List<SensorSample> buf, List<double> achse, List<double> bias) {
    const gyroWeight = 0.05; // App-Formel (SignalProcessor)
    final n = buf.length;
    final gP = List<double>.filled(n, 0.0);
    final gyroMag = List<double>.filled(n, 0.0);
    final combinedRaw = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      final s = buf[i];
      final dx = s.gx - bias[0];
      final dy = s.gy - bias[1];
      final dz = s.gz - bias[2];
      gP[i] = dx * achse[0] + dy * achse[1] + dz * achse[2];
      gyroMag[i] = sqrt(dx * dx + dy * dy + dz * dz);
      combinedRaw[i] = s.accelMagnitude + gyroWeight * gyroMag[i];
    }
    return {
      ChosenSignal.gP: gP,
      ChosenSignal.combined: _ema(combinedRaw, 0.6),
      ChosenSignal.gyroMag: gyroMag,
    };
  }

  /// Baseline/Sigma je Kandidaten-Signal aus den Ruhe-Rändern der
  /// Aufzeichnung (je 1 s am Anfang und Ende, Referenz metaB).
  Map<ChosenSignal, (double, double)> _signalMeta(
      Map<ChosenSignal, List<double>> signale) {
    final nRest = sampleRateHz.round();
    final result = <ChosenSignal, (double, double)>{};
    for (final e in signale.entries) {
      final sig = e.value;
      final rest = <double>[
        ...sig.sublist(0, min(nRest, sig.length)),
        ...sig.sublist(max(0, sig.length - nRest)),
      ];
      result[e.key] = (_median(rest), _std(rest));
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Tap-to-Tag (Referenz: Konzept §2.6 "Tap-to-Tag im Detail", V2)
  // ---------------------------------------------------------------------

  /// Sucht rueckwaerts vom rohen Tap-Sample-Index [rohIndex] das naechste
  /// Signal-Landmark: das lokale Minimum von [gyroMag] in einem
  /// [fensterSamples] grossen Fenster davor (Konzept §2.6: "lokales
  /// Minimum des Winkels bzw. Gyro-Nulldurchgang Richtung Ruhe" - ein
  /// Tap markiert "Rep fertig", die Rotationsgeschwindigkeit sollte dort
  /// gerade Richtung Ruhe zurueckgehen).
  int _naechstesLandmark(
      List<double> gyroMag, int rohIndex, int fensterSamples) {
    if (gyroMag.isEmpty) return rohIndex;
    final ende = min(rohIndex, gyroMag.length - 1);
    final start = max(0, ende - fensterSamples);
    var minIdx = ende;
    var minVal = gyroMag[ende];
    for (var i = start; i <= ende; i++) {
      if (gyroMag[i] < minVal) {
        minVal = gyroMag[i];
        minIdx = i;
      }
    }
    return minIdx;
  }

  /// Lag-korrigierte Tap-Indizes (Konzept §2.6): jeder rohe Tap wird auf
  /// sein naechstes Landmark ausgerichtet, DANACH wird ein EINZIGER,
  /// gemeinsamer Median-Lag ueber alle Taps abgezogen - nicht pro Tap
  /// individuell verrechnet, sondern ein personentypischer
  /// Korrekturwert (Reaktionszeit ist relativ konstant pro Person).
  /// Leere Eingabe -> leere Ausgabe (kein Tap gedrueckt).
  List<int> _lagKorrigierteTaps(List<int> rohTaps, List<double> gyroMag) {
    if (rohTaps.isEmpty) return const [];
    // 500ms @ 50Hz - deckt den im Konzept genannten Lag-Bereich
    // (150-400ms) mit Marge ab.
    final fensterSamples = (0.5 * sampleRateHz).round();
    final landmarks = [
      for (final t in rohTaps) _naechstesLandmark(gyroMag, t, fensterSamples)
    ];
    final lags = [
      for (var i = 0; i < rohTaps.length; i++)
        (rohTaps[i] - landmarks[i]).toDouble()
    ];
    final medianLag = _median(lags).round();
    return [for (final t in rohTaps) t - medianLag];
  }

  /// true, wenn jedes durch [taps] definierte Intervall (0..taps[0],
  /// taps[0]..taps[1], ...) genau eine Detektion aus [marks] enthaelt
  /// (Konzept §3 Stufe B: "jedes Tap-Intervall muss genau 1 Detektion
  /// enthalten"). Leere [taps] -> immer true (keine Taps = keine
  /// zusaetzliche Pruefung, Known-Count-Sweep verhaelt sich unveraendert).
  bool _tapsAligned(List<int> taps, List<RepMark> marks) {
    if (taps.isEmpty) return true;
    var grenzeVorher = -1;
    for (final grenze in taps) {
      final anzahlImFenster = marks
          .where(
              (m) => m.sampleIndex > grenzeVorher && m.sampleIndex <= grenze)
          .length;
      if (anzahlImFenster != 1) return false;
      grenzeVorher = grenze;
    }
    return true;
  }

  _SweepCfg? _knownCountSweep(
    Map<ChosenSignal, List<double>> signale,
    Map<ChosenSignal, (double, double)> meta,
    double t0,
    int nSoll,
    List<int> tapsKorrigiert,
  ) {
    _SweepCfg? beste;
    for (final e in signale.entries) {
      final name = e.key;
      final sig = e.value;
      final (baseline, sigma) = meta[name]!;
      final span = _percentile(sig, 99) - baseline;
      if (span <= 0) continue;
      final vorl = _zaehleEdge(
          sig, sampleRateHz, baseline + 3 * sigma, 0.35 * t0, baseline);
      final prom = vorl.length >= 3
          ? 0.2 * _median([for (final mark in vorl) mark.height])
          : 0.0;
      // Tempo-Sonde: 3× gestrecktes Signal (simuliert deutlich langsameres
      // Tempo). Eine valide Konfiguration muss auch dort n_soll zählen.
      final sigLangsam = _stretch3(sig);
      for (final frac in _linspace(0.10, 1.00, 20)) {
        final theta = baseline + frac * span;
        for (final prominenz in [0.0, prom]) {
          // Stabilitäts-Sonde: (theta, prominenz) muss auch mit der
          // kürzesten Refractory (0,35·T0) noch n_soll zählen — sonst
          // maskiert eine lange Refractory echte Signal-Buckel.
          if (_zaehleEdge(sig, sampleRateHz, theta, 0.35 * t0, baseline,
                  prominenz: prominenz)
                  .length !=
              nSoll) {
            continue;
          }
          if (_zaehleEdge(sigLangsam, sampleRateHz, theta, 0.35 * t0,
                  baseline,
                  prominenz: prominenz)
                  .length !=
              nSoll) {
            continue;
          }
          for (final refrFaktor in _linspace(0.35, 0.75, 5)) {
            final refr = refrFaktor * t0;
            final reps = _zaehleEdge(
                sig, sampleRateHz, theta, refr, baseline,
                prominenz: prominenz);
            if (reps.length != nSoll) continue;
            // Tap-Alignment (Konzept §3 Stufe B, V2): mit Taps vorhanden
            // muss JEDES Tap-Intervall genau 1 Detektion enthalten - eine
            // Konfiguration, die zufaellig die richtige ANZAHL trifft,
            // aber an der falschen Stelle zaehlt (z. B. zwei Detektionen
            // in einer Rep, keine in der naechsten), faellt hier durch,
            // obwohl reps.length == nSoll. Leere Tap-Liste (kein addTap()
            // aufgerufen) -> immer true, siehe _tapsAligned.
            if (!_tapsAligned(tapsKorrigiert, reps)) continue;
            // Höhen-Gate: Detektionen müssen die obere Signalrange
            // erreichen (echte Rep-Peaks), nicht Flanken-Rauschen.
            final hoehen = [for (final mark in reps) mark.height];
            if (_median(hoehen) < baseline + 0.5 * span) continue;
            final intervalle = <double>[
              for (var i = 1; i < reps.length; i++)
                (reps[i].sampleIndex - reps[i - 1].sampleIndex) /
                    sampleRateHz,
            ];
            final meanI = _mean(intervalle);
            final cv = intervalle.length > 1 && meanI > 0
                ? _std(intervalle) / meanI
                : double.infinity;
            final margin = theta - (baseline + 3 * sigma);
            final cfg = _SweepCfg(
              signal: name,
              theta: theta,
              refractoryS: refr,
              prominenz: prominenz,
              cv: cv,
              margin: margin,
              peakHoehen: hoehen,
            );
            if (beste == null || _isBetter(cfg, beste)) beste = cfg;
          }
        }
      }
    }
    return beste;
  }

  /// Tie-Break der Referenz: Schlüssel (cv, −margin), lexikographisch —
  /// erst minimaler Variationskoeffizient der Intervalle, dann maximale
  /// Margin über dem Rauschboden.
  bool _isBetter(_SweepCfg a, _SweepCfg b) {
    if (a.cv != b.cv) return a.cv < b.cv;
    return a.margin > b.margin;
  }

  /// Finale Schwelle = median − k·MAD der validierten Peak-Höhen
  /// (Referenz median_minus_k_mad). Bei praktisch verschwindendem MAD
  /// bleibt die Sweep-Schwelle erhalten.
  (double, double, double, double) _medianMinusKMad(
      List<double> peakHoehen, double thetaSweep) {
    final med = _median(peakHoehen);
    final mad = _median([for (final h in peakHoehen) (h - med).abs()]);
    if (mad < 1e-9) return (thetaSweep, 0.0, med, mad);
    final k = max(0.0, (med - thetaSweep) / mad);
    return (med - k * mad, k, med, mad);
  }

  // ---------------------------------------------------------------------
  // Stufe C: Tempo-Robustheit (Referenz stufeC_tempo_robustheit)
  // ---------------------------------------------------------------------

  ({double theta, bool ok, bool angepasst}) _stufeC(
    List<double> sigB,
    List<double> sigC,
    double baseline,
    _SweepCfg cfg,
    int nB,
    int nC,
  ) {
    int zaehl(List<double> sig, double theta) => _zaehleEdge(
            sig, sampleRateHz, theta, cfg.refractoryS, baseline,
            prominenz: cfg.prominenz)
        .length;
    List<double> hoehen(List<double> sig, double theta) => [
          for (final mark in _zaehleEdge(
              sig, sampleRateHz, theta, cfg.refractoryS, baseline,
              prominenz: cfg.prominenz))
            mark.height
        ];

    final theta0 = cfg.theta;
    double? thetaArbeit;
    if (zaehl(sigC, theta0) == nC && zaehl(sigB, theta0) == nB) {
      thetaArbeit = theta0;
    } else {
      for (final f in _linspace(0.98, 0.05, 60)) {
        final thetaT = baseline + (theta0 - baseline) * f;
        if (zaehl(sigB, thetaT) == nB && zaehl(sigC, thetaT) == nC) {
          thetaArbeit = thetaT;
          break;
        }
      }
      if (thetaArbeit == null) {
        return (theta: theta0, ok: false, angepasst: false);
      }
    }
    // Konservativer Deckel: untere Verteilungskante der langsamen Peaks,
    // damit die Schwelle nicht am schwächsten beobachteten Peak klebt.
    final langsamHoehen = hoehen(sigC, thetaArbeit);
    if (langsamHoehen.isNotEmpty && cfg.peakHoehen.isNotEmpty) {
      final medB = _median(cfg.peakHoehen);
      final madB = _median([for (final h in cfg.peakHoehen) (h - medB).abs()]);
      final sigmaRel = max(1.4826 * madB / max(medB, 1e-9), 0.10);
      final medC = _median(langsamHoehen);
      final deckel = medC - 2.5 * sigmaRel * medC;
      final thetaDeckel = min(thetaArbeit, deckel);
      if (thetaDeckel < thetaArbeit - 1e-9 &&
          zaehl(sigB, thetaDeckel) == nB &&
          zaehl(sigC, thetaDeckel) == nC) {
        return (theta: thetaDeckel, ok: true, angepasst: true);
      }
    }
    return (
      theta: thetaArbeit,
      ok: true,
      angepasst: (thetaArbeit - theta0).abs() > 1e-9,
    );
  }

  // ---------------------------------------------------------------------
  // Zählpfad (Referenz zaehle_edge): Rising Edge über theta mit
  // Refractory, Falling Edge baseline-relativ (falling_ratio 0,5) mit
  // 4-Sample-Debounce, optionale Prominenz.
  // ---------------------------------------------------------------------

  List<RepMark> _zaehleEdge(
    List<double> signal,
    double hz,
    double theta,
    double refractoryS,
    double baseline, {
    double fallingRatio = 0.5,
    double prominenz = 0.0,
    int fallingDebounce = 4,
  }) {
    final reps = <RepMark>[];
    var above = false;
    var excPeak = double.negativeInfinity;
    var excIdx = -1;
    var preMin = double.infinity;
    var lastEnd = -1000000000000;
    var unterFalling = 0;
    final refrSamples = refractoryS * hz;
    final falling = baseline + (theta - baseline) * fallingRatio;
    for (var i = 0; i < signal.length; i++) {
      final v = signal[i];
      if (!above) {
        if (v < preMin) preMin = v;
        if (v > theta) {
          if (i - lastEnd < refrSamples) continue; // Refractory-Sperrzeit
          above = true;
          excPeak = v;
          excIdx = i;
          unterFalling = 0;
        }
      } else {
        if (v >= excPeak) {
          excPeak = v;
          excIdx = i;
        }
        if (v < falling) {
          unterFalling++;
        } else {
          unterFalling = 0;
        }
        if (unterFalling >= fallingDebounce) {
          above = false;
          unterFalling = 0;
          if (prominenz > 0.0 && (excPeak - preMin) < prominenz) {
            preMin = v;
            continue; // zu flacher Ausschlag → keine Rep
          }
          reps.add(RepMark(excIdx, excPeak));
          lastEnd = i;
          preMin = v;
        }
      }
    }
    return reps;
  }
}

// -----------------------------------------------------------------------
// Interne Ergebnis-Typen + numerische Helfer (rein, ohne Controller-State)
// -----------------------------------------------------------------------

class _RestStats {
  final int n;
  final double baseline;
  final double sigmaAccel;
  final List<double> gyroBias;
  final double sigmaGyro;
  final double gyroMagMean;
  final bool gateOk;

  const _RestStats({
    required this.n,
    required this.baseline,
    required this.sigmaAccel,
    required this.gyroBias,
    required this.sigmaGyro,
    required this.gyroMagMean,
    required this.gateOk,
  });
}

class _AxisResult {
  final List<double> achse;
  final double t0;
  final int i0;
  final int i1;
  final double gyroPeakFenster;
  final double varianzAnteil;

  const _AxisResult({
    required this.achse,
    required this.t0,
    required this.i0,
    required this.i1,
    required this.gyroPeakFenster,
    required this.varianzAnteil,
  });
}

class _SweepCfg {
  final ChosenSignal signal;
  double theta;
  final double refractoryS;
  final double prominenz;
  final double cv;
  final double margin;
  final List<double> peakHoehen;

  _SweepCfg({
    required this.signal,
    required this.theta,
    required this.refractoryS,
    required this.prominenz,
    required this.cv,
    required this.margin,
    required this.peakHoehen,
  });
}

double _mean(List<double> xs) =>
    xs.isEmpty ? 0.0 : xs.fold<double>(0.0, (a, b) => a + b) / xs.length;

/// Population-Standardabweichung (ddof=0), wie numpy.std in der Referenz.
double _std(List<double> xs) {
  if (xs.isEmpty) return 0.0;
  final m = _mean(xs);
  return sqrt(_mean([for (final x in xs) (x - m) * (x - m)]));
}

double _median(List<double> xs) {
  if (xs.isEmpty) return 0.0;
  final s = List<double>.of(xs)..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// numpy.percentile mit linearer Interpolation (Default-Methode).
double _percentile(List<double> xs, double p) {
  if (xs.isEmpty) return 0.0;
  final s = List<double>.of(xs)..sort();
  final rank = (s.length - 1) * p / 100.0;
  final i = rank.floor();
  final f = rank - i;
  if (i + 1 >= s.length) return s.last;
  return s[i] * (1 - f) + s[i + 1] * f;
}

List<double> _linspace(double a, double b, int n) {
  if (n <= 1) return [a];
  final step = (b - a) / (n - 1);
  return [for (var i = 0; i < n; i++) a + i * step];
}

/// Kausaler EMA-Tiefpass wie SignalProcessor (Referenz ema_glaettung).
List<double> _ema(List<double> xs, double alpha) {
  if (xs.isEmpty) return [];
  final out = List<double>.filled(xs.length, 0.0);
  out[0] = xs[0];
  for (var i = 1; i < xs.length; i++) {
    out[i] = out[i - 1] * (1 - alpha) + xs[i] * alpha;
  }
  return out;
}

/// Tempo-Sonde: Signal linear um Faktor 3 gestreckt (Referenz np.interp
/// über arange(0, n−1, 1/3)).
List<double> _stretch3(List<double> sig) {
  final n = sig.length;
  if (n < 2) return List<double>.of(sig);
  final m = 3 * (n - 1);
  final out = List<double>.filled(m, 0.0);
  for (var k = 0; k < m; k++) {
    final x = k / 3.0;
    final i = x.floor();
    final f = x - i;
    out[k] = sig[i] * (1 - f) + sig[i + 1] * f;
  }
  return out;
}

/// Jacobi-Eigenzerlegung einer symmetrischen 3×3-Matrix (Konzept „Neue
/// Dependencies": PCA auf 3D-Gyro braucht nur 3×3, kein Package nötig).
/// Rückgabe: Eigenwerte w und Eigenvektoren v (Spalten).
({List<double> w, List<List<double>> v}) _jacobiEigen3(
    List<List<double>> aIn) {
  final a = [for (final r in aIn) List<double>.from(r)];
  final v = [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
  ];
  for (var sweep = 0; sweep < 64; sweep++) {
    final off =
        sqrt(a[0][1] * a[0][1] + a[0][2] * a[0][2] + a[1][2] * a[1][2]);
    if (off < 1e-12) break;
    for (var p = 0; p < 2; p++) {
      for (var q = p + 1; q < 3; q++) {
        if (a[p][q].abs() < 1e-15) continue;
        final phi = (a[q][q] - a[p][p]) / (2 * a[p][q]);
        final t = (phi >= 0 ? 1.0 : -1.0) / (phi.abs() + sqrt(phi * phi + 1));
        final c = 1 / sqrt(t * t + 1);
        final s = t * c;
        for (var k = 0; k < 3; k++) {
          final akp = a[k][p];
          final akq = a[k][q];
          a[k][p] = c * akp - s * akq;
          a[k][q] = s * akp + c * akq;
        }
        for (var k = 0; k < 3; k++) {
          final apk = a[p][k];
          final aqk = a[q][k];
          a[p][k] = c * apk - s * aqk;
          a[q][k] = s * apk + c * aqk;
        }
        for (var k = 0; k < 3; k++) {
          final vkp = v[k][p];
          final vkq = v[k][q];
          v[k][p] = c * vkp - s * vkq;
          v[k][q] = s * vkp + c * vkq;
        }
      }
    }
  }
  return (w: [a[0][0], a[1][1], a[2][2]], v: v);
}
