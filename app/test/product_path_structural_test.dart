import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Product wiring gates for 1.0 — drive real source files, not reimplemented logic.
void main() {
  test('product main: autoEndSetEnabled is false', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('autoEndSetEnabled: false'), isTrue,
        reason: 'sets must not auto-timeout-end in product build');
  });

  test('home_screen exposes Satz beenden → endSetManually', () {
    final home = File('lib/presentation/screens/home_screen.dart').readAsStringSync();
    expect(home.contains('Satz beenden'), isTrue);
    expect(home.contains('endSetManually'), isTrue);
  });

  test('engine_provider correction learns via nudge + never rewrites countedReps',
      () {
    final p =
        File('lib/presentation/providers/engine_provider.dart').readAsStringSync();
    expect(p.contains('_learnFromCorrection'), isTrue);
    expect(p.contains('nudgeDirectionAwareThreshold'), isTrue);
    expect(p.contains('saveCorrection'), isTrue);
    // Spec: only correctedReps is set on the set, not countedReps mutation.
    expect(p.contains('copyWith(correctedReps: userReps)'), isTrue);
    expect(
      p.contains('countedReps = userReps') ||
          p.contains('countedReps: userReps'),
      isFalse,
      reason: 'must not rewrite countedReps from user correction',
    );
  });

  test('correction dialog has Speichern & lernen; no user-facing KI-lernt string',
      () {
    final d =
        File('lib/presentation/widgets/correction_dialog.dart').readAsStringSync();
    expect(d.contains('Speichern & lernen'), isTrue);
    // Doc may mention the forbidden phrase as a negative; UI Text(...) must not.
    expect(d.contains("Text('Die KI lernt"), isFalse);
    expect(d.contains('Text("Die KI lernt'), isFalse);
    expect(RegExp(r"thankYouMessage\s*=\s*[^;]*KI lernt").hasMatch(d), isFalse);
  });

  test('_useNewPipeline remains false', () {
    final engine = File('lib/domain/workout_engine.dart').readAsStringSync();
    expect(engine.contains('bool _useNewPipeline = false'), isTrue);
  });
}
