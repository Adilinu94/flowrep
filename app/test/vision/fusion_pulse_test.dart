import 'package:flutter_test/flutter_test.dart';
import 'package:flowrep/domain/vision/fusion_engine.dart';
import 'package:flowrep/domain/vision/fusion_pulse.dart';

void main() {
  group('FusionPulseController E7', () {
    test('pulseScale peaks when fusedReps increases', () {
      final p = FusionPulseController(pulseDurationMs: 300, peakScale: 2.0);
      expect(p.pulseScale, 1.0);
      p.onFrame(nowMs: 1000, lastDecision: null, fusedReps: 0);
      expect(p.pulseScale, 1.0);
      p.onFrame(nowMs: 1100, lastDecision: null, fusedReps: 1);
      expect(p.pulseScale, 2.0);
      p.onFrame(nowMs: 1500, lastDecision: null, fusedReps: 1);
      expect(p.pulseScale, 1.0);
    });

    test('both source decision can trigger pulse', () {
      final p = FusionPulseController(pulseDurationMs: 200, peakScale: 1.5);
      const decision = FusionResult(
        shouldCount: true,
        source: RepSource.both,
        confidence: 0.9,
        diagnostic: 'both',
      );
      p.onFrame(nowMs: 1000, lastDecision: decision, fusedReps: 0);
      expect(p.pulseScale, 1.5);
    });

    test('reset clears pulse', () {
      final p = FusionPulseController();
      p.debugTrigger(1000);
      expect(p.pulseScale, greaterThan(1.0));
      p.reset();
      expect(p.pulseScale, 1.0);
    });
  });
}
