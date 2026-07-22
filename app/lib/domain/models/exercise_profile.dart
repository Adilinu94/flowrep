/// Kalibrierungs-Profil pro Übung ("ExerciseProfile", Konzept 2.0, §3 Stufe D
/// und §6 Multi-Exercise-Statement in
/// docs/KONZEPT_GUIDED_CALIBRATION_2_0_2026-07-16.md).
///
/// Ersetzt die bisherigen zwei Einzelwerte (peakThreshold,
/// minThresholdAboveBaseline) durch ein vollständiges, per `exerciseId`
/// gekeyetes Profil. V1 implementiert ausschließlich 'bicep_curl' — Modell,
/// Store und Migration sind aber so angelegt, dass Übung #2 später "ein
/// Profil hinzufügen" ist statt "Pipeline umbauen" (RECHERCHE_99 §2.4).
library;

/// Schema-Version des Profils/Stores. 1 = Legacy (zwei Einzelwerte),
/// 2 = ExerciseProfile (dieses Modell).
const int kProfileSchemaVersion = 2;

/// V1: einzige unterstützte Übung.
const String kDefaultExerciseId = 'bicep_curl';

/// Kandidaten-Signal, auf dem die Known-Count-Optimierung gezählt hat
/// (Konzept §3 Stufe B). Die Einheit von [ExerciseProfile.theta] hängt vom
/// gewählten Signal ab: gP in °/s, combined in g + 0,05·°/s, gyroMag in °/s.
enum ChosenSignal { gP, combined, gyroMag }

ChosenSignal _signalFromString(String s) => ChosenSignal.values.firstWhere(
      (e) => e.name == s,
      orElse: () => ChosenSignal.combined,
    );

/// Immutables Kalibrierungs-Ergebnis einer Übung.
class ExerciseProfile {
  final String exerciseId;

  /// Gelernte Rotationsachse (Einheitsvektor, Stufe A, PCA 3×3).
  final List<double> rotationAxis;

  /// Signal, auf dem gezählt wird (Stufe B, durch den Sweep gewählt).
  final ChosenSignal chosenSignal;

  /// Gelernte Schwelle in der Einheit von [chosenSignal].
  final double theta;

  /// Refractory / Mindest-Rep-Abstand in Sekunden (Stufe B).
  final double minRepIntervalSeconds;

  /// Mindest-Prominenz (Ausschlag über dem vorausgehenden Tal), 0 = aus.
  final double prominenceMin;

  /// Median/MAD der Rep-Dauern der Kalibrierung (Sekunden).
  final double medianTSeconds;
  final double madTSeconds;

  /// Gyro-Bias aus der Ruhephase (Stufe 0), 3 Werte in °/s.
  final List<double> gyroBias;

  /// Init-Werte für duale adaptive Schwellen (Pan-Tompkins-Transfer, V3).
  final double? spkInit;
  final double? npkInit;

  // === NEU (Calibration 2.0, SPEC TEIL 4.1) ===

  /// Rep-Template (64 normalisierte Werte) für Template-Matching.
  /// Null wenn kein Template extrahiert wurde (z.B. zu wenige Reps).
  final List<double>? repTemplate;

  /// NCC-Schwelle für Template-Akzeptanz (Standard: 0.65).
  final double templateCorrThreshold;

  /// Erwartete Prominenz in °/s (aus Kalibrierung, für ROM-Validierung).
  final double? expectedProminence;

  /// Toleranz für Prominenz-Abweichung (Standard: 0.3 = ±30%).
  final double prominenceTolerance;

  /// Erwartetes Verhältnis konzentrische/exzentrische Phase (Standard: null = frei).
  final double? concentricRatioExpected;

  /// Minimales Dauer-Verhältnis (positive/negative Phase, Standard: 0.5).
  final double durationRatioMin;

  /// Maximales Dauer-Verhältnis (Standard: 3.0).
  final double durationRatioMax;

  /// Qualitätsmaß 0..1 (aus Regularität CV und Konsistenz der Stufen).
  final double qualityScore;

  final DateTime calibratedAt;

  /// 0 = frisch kalibriert (v2), 1 = aus dem Legacy-Format migriert.
  final int migratedFrom;

  const ExerciseProfile({
    required this.exerciseId,
    required this.rotationAxis,
    required this.chosenSignal,
    required this.theta,
    required this.minRepIntervalSeconds,
    this.prominenceMin = 0.0,
    required this.medianTSeconds,
    required this.madTSeconds,
    required this.gyroBias,
    this.spkInit,
    this.npkInit,
    this.repTemplate,
    this.templateCorrThreshold = 0.65,
    this.expectedProminence,
    this.prominenceTolerance = 0.3,
    this.concentricRatioExpected,
    this.durationRatioMin = 0.5,
    this.durationRatioMax = 3.0,
    required this.qualityScore,
    required this.calibratedAt,
    this.migratedFrom = 0,
  });

  /// Rekalibrierungs-Empfehlung (Konzept §6 Migration): migrierte oder
  /// qualitativ schwache Profile sollen aktiv neu kalibriert werden.
  bool get needsRecalibration => migratedFrom == 1 || qualityScore < 0.5;

  /// Migration v1→v2 (Konzept §6): die Legacy-Einzelwerte werden in ein
  /// minimales Profil gewrapt — funktional, aber mit niedrigem
  /// [qualityScore], damit die App eine Rekalibrierung empfiehlt.
  factory ExerciseProfile.legacy({
    required String exerciseId,
    required double peakThreshold,
    required double minThresholdAboveBaseline,
  }) {
    return ExerciseProfile(
      exerciseId: exerciseId,
      rotationAxis: const [1.0, 0.0, 0.0],
      chosenSignal: ChosenSignal.combined,
      theta: peakThreshold,
      minRepIntervalSeconds: 0.8,
      prominenceMin: 0.0,
      medianTSeconds: 1.6,
      madTSeconds: 0.0,
      gyroBias: const [0.0, 0.0, 0.0],
      qualityScore: 0.2,
      calibratedAt: DateTime.fromMillisecondsSinceEpoch(0),
      migratedFrom: 1,
    );
  }

  /// Bayesianisches Blending (Konzept §2.2/§3 Stufe D): bei Rekalibrierung
  /// wird gegen das Vorgänger-Profil gemischt, statt komplett zu ersetzen —
  /// eine schlechte Rekalibrierung kann das Profil nie ruinieren.
  /// [weight] ∈ [0,1]: Anteil der NEUEN Messung (aus Anzahl/Konsistenz).
  ExerciseProfile blendWith(ExerciseProfile neu, double weight) {
    final w = weight.clamp(0.0, 1.0);
    double mix(double a, double b) => a * (1 - w) + b * w;
    List<double> mix3(List<double> a, List<double> b) =>
        [mix(a[0], b[0]), mix(a[1], b[1]), mix(a[2], b[2])];
    return ExerciseProfile(
      exerciseId: exerciseId,
      rotationAxis: mix3(rotationAxis, neu.rotationAxis),
      // Signal-Wahl ist diskret: sie folgt der neuen Messung, wenn deren
      // Gewicht dominiert, sonst die bisherige.
      chosenSignal: w >= 0.5 ? neu.chosenSignal : chosenSignal,
      theta: mix(theta, neu.theta),
      minRepIntervalSeconds:
          mix(minRepIntervalSeconds, neu.minRepIntervalSeconds),
      prominenceMin: mix(prominenceMin, neu.prominenceMin),
      medianTSeconds: mix(medianTSeconds, neu.medianTSeconds),
      madTSeconds: mix(madTSeconds, neu.madTSeconds),
      gyroBias: mix3(gyroBias, neu.gyroBias),
      spkInit: neu.spkInit ?? spkInit,
      npkInit: neu.npkInit ?? npkInit,
      // Template: neues Template übernimmt (diskret, kein Blending).
      repTemplate: neu.repTemplate ?? repTemplate,
      templateCorrThreshold: mix(templateCorrThreshold, neu.templateCorrThreshold),
      expectedProminence: neu.expectedProminence != null
          ? mix(expectedProminence ?? neu.expectedProminence!, neu.expectedProminence!)
          : expectedProminence,
      prominenceTolerance: mix(prominenceTolerance, neu.prominenceTolerance),
      concentricRatioExpected: neu.concentricRatioExpected ?? concentricRatioExpected,
      durationRatioMin: mix(durationRatioMin, neu.durationRatioMin),
      durationRatioMax: mix(durationRatioMax, neu.durationRatioMax),
      qualityScore: neu.qualityScore,
      calibratedAt: neu.calibratedAt,
      migratedFrom: 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'rotationAxis': rotationAxis,
        'chosenSignal': chosenSignal.name,
        'theta': theta,
        'minRepIntervalSeconds': minRepIntervalSeconds,
        'prominenceMin': prominenceMin,
        'medianTSeconds': medianTSeconds,
        'madTSeconds': madTSeconds,
        'gyroBias': gyroBias,
        'spkInit': spkInit,
        'npkInit': npkInit,
        'repTemplate': repTemplate,
        'templateCorrThreshold': templateCorrThreshold,
        'expectedProminence': expectedProminence,
        'prominenceTolerance': prominenceTolerance,
        'concentricRatioExpected': concentricRatioExpected,
        'durationRatioMin': durationRatioMin,
        'durationRatioMax': durationRatioMax,
        'qualityScore': qualityScore,
        'calibratedAt': calibratedAt.toIso8601String(),
        'migratedFrom': migratedFrom,
      };

  factory ExerciseProfile.fromJson(Map<String, dynamic> json) {
    List<double> vec(dynamic v) =>
        (v as List).map((e) => (e as num).toDouble()).toList();
    return ExerciseProfile(
      exerciseId: json['exerciseId'] as String? ?? kDefaultExerciseId,
      rotationAxis: vec(json['rotationAxis'] ?? const [1.0, 0.0, 0.0]),
      chosenSignal: _signalFromString(json['chosenSignal'] as String? ?? ''),
      theta: (json['theta'] as num).toDouble(),
      minRepIntervalSeconds:
          (json['minRepIntervalSeconds'] as num?)?.toDouble() ?? 0.8,
      prominenceMin: (json['prominenceMin'] as num?)?.toDouble() ?? 0.0,
      medianTSeconds: (json['medianTSeconds'] as num?)?.toDouble() ?? 1.6,
      madTSeconds: (json['madTSeconds'] as num?)?.toDouble() ?? 0.0,
      gyroBias: vec(json['gyroBias'] ?? const [0.0, 0.0, 0.0]),
      spkInit: (json['spkInit'] as num?)?.toDouble(),
      npkInit: (json['npkInit'] as num?)?.toDouble(),
      repTemplate: json['repTemplate'] != null
          ? (json['repTemplate'] as List).map((e) => (e as num).toDouble()).toList()
          : null,
      templateCorrThreshold:
          (json['templateCorrThreshold'] as num?)?.toDouble() ?? 0.65,
      expectedProminence: (json['expectedProminence'] as num?)?.toDouble(),
      prominenceTolerance:
          (json['prominenceTolerance'] as num?)?.toDouble() ?? 0.3,
      concentricRatioExpected:
          (json['concentricRatioExpected'] as num?)?.toDouble(),
      durationRatioMin:
          (json['durationRatioMin'] as num?)?.toDouble() ?? 0.5,
      durationRatioMax:
          (json['durationRatioMax'] as num?)?.toDouble() ?? 3.0,
      qualityScore: (json['qualityScore'] as num?)?.toDouble() ?? 0.2,
      calibratedAt: DateTime.tryParse(json['calibratedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      migratedFrom: (json['migratedFrom'] as num?)?.toInt() ?? 0,
    );
  }
}
