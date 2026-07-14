import 'package:flutter/foundation.dart';

/// Structured logger replacing raw print() statements throughout the app.
///
/// In debug builds, all log levels are printed. In release builds, only
/// warnings and errors are printed — debug/info are silently dropped.
///
/// See ADR-014 and docs/ARCHITECTURE_REVIEW_2026-07-12.md §4.
class AppLogger {
  AppLogger._();

  /// Log a debug message. Printed only in debug mode.
  static void d(String message) {
    // ignore: avoid_print
    if (kDebugMode) print('[FlowRep:D] $message');
  }

  /// Log an informational message. Printed only in debug mode.
  static void i(String message) {
    // ignore: avoid_print
    if (kDebugMode) print('[FlowRep:I] $message');
  }

  /// Log a warning. Printed in both debug and release modes.
  static void w(String message) {
    // ignore: avoid_print
    print('[FlowRep:W] $message');
  }

  /// Log an error. Always printed.
  static void e(String message) {
    // ignore: avoid_print
    print('[FlowRep:E] $message');
  }
}
