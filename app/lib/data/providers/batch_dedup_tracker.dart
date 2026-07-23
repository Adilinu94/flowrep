/// Agent 1 / Schritt C (docs/archive/umbauplan/agenten-baupläne/
/// AGENT_1_SIGNAL_PIPELINE.md, RECHERCHE_ZAEHLROBUSTHEIT_2026-07-16.md S5):
/// pure, BLE-independent dedup + gap-detection logic, extracted out of
/// [BleSensorProvider]'s polling loop so it can be unit-tested without a
/// real or mocked Bluetooth stack.
///
/// Background: `BleSensorProvider._startPolling()` reads the SensorData
/// characteristic in a tight loop (HyperOS drops GATT notifications, see
/// the comment there) rather than being notified. The same on-wire batch
/// can therefore be read more than once before the firmware produces a new
/// one, and - the actual S5 concern - the reverse can also happen: if
/// polling were ever slower than the firmware's update rate, an entire
/// batch could be silently overwritten and never read at all. The
/// original code only handled the first case, and even that only as a
/// bare `if (x == last) continue;` with no visibility into how often it
/// happened.
///
/// Since docs/reference/protocol.yaml v2 (Agent 4, 2026-07-17), the firmware's
/// honestly-paced batch rate is 12.5 Hz (80ms/batch: 4 samples x 20ms) -
/// slower than this app's ~30 Hz poll rate, so in practice polling should
/// now comfortably outrun the firmware and catch every batch. This class
/// doesn't change that behaviour; it makes it OBSERVABLE either way,
/// instead of asserting it and never checking again.
class BatchDedupTracker {
  BatchDedupTracker({this.expectedBatchIntervalMs = 80});

  /// Nominal time between two genuinely different batches, per
  /// docs/reference/protocol.yaml `timing:` (4 samples x sample_interval_ms).
  /// Only used to size the missed-batch estimate below, not for the
  /// duplicate check itself (which is an exact equality test).
  final int expectedBatchIntervalMs;

  int? _lastTimestampMs;
  int _duplicateSkips = 0;
  int _estimatedMissedBatches = 0;

  /// How many `read()` results were byte-for-byte the same batch as the
  /// one before (the case the original code silently handled).
  int get duplicateSkips => _duplicateSkips;

  /// Rough estimate of batches that likely existed on the firmware side
  /// but were never seen by a `read()` call at all - inferred from gaps
  /// between accepted timestamps that are meaningfully larger than
  /// [expectedBatchIntervalMs]. Zero does not guarantee nothing was ever
  /// missed (a dropped batch immediately followed by another dropped one
  /// could in principle look like a single, larger-but-not-flagged gap
  /// depending on rounding) - it guarantees this class isn't silently
  /// discarding evidence of loss the way the pre-Schritt-C code did.
  int get estimatedMissedBatches => _estimatedMissedBatches;

  /// Feed the next batch's wire timestamp (milliseconds, as read directly
  /// from the packet). Returns true if this batch should be SKIPPED as a
  /// duplicate of the last one processed, false if it's new data the
  /// caller should actually parse and forward.
  bool shouldSkip(int timestampMs) {
    final last = _lastTimestampMs;
    if (last == null) {
      _lastTimestampMs = timestampMs;
      return false;
    }

    if (timestampMs == last) {
      _duplicateSkips++;
      return true;
    }

    final elapsed = timestampMs - last;
    // Negative or implausibly large elapsed: a reconnect (timestamps
    // restart near 0 relative to the new session) or a millis() overflow
    // (wraps every ~49.7 days) rather than a genuine gap - don't count
    // either as "missed batches", just resynchronise silently.
    if (elapsed > 0 && elapsed < expectedBatchIntervalMs * 1000) {
      final intervalsElapsed = elapsed / expectedBatchIntervalMs;
      // Round rather than floor: a batch arriving a few ms later than the
      // nominal interval (normal jitter) should round back down to 1
      // interval elapsed (0 missed), not be counted as a near-miss.
      final missed = intervalsElapsed.round() - 1;
      if (missed > 0) _estimatedMissedBatches += missed;
    }

    _lastTimestampMs = timestampMs;
    return false;
  }

  /// Reset all tracking - call on reconnect, matching the equivalent
  /// reset the original `_lastBatchTimestampMs = -1` line did in
  /// `_startPolling()`.
  void reset() {
    _lastTimestampMs = null;
    _duplicateSkips = 0;
    _estimatedMissedBatches = 0;
  }
}
