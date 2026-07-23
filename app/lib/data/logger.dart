import 'package:flutter/foundation.dart';

/// Structured logger for FlowRep (ADR-014 / P1-1 / P2-7).
///
/// In debug builds, all log levels are printed. In release builds, only
/// warnings and errors are printed — debug/info are silently dropped.
class AppLogger {
  AppLogger._();

  static const String _tag = 'FlowRep';

  /// Log a debug message. Printed only in debug mode.
  static void d(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[$_tag:D] $message');
    }
  }

  /// Log an informational message. Printed only in debug mode.
  static void i(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[$_tag:I] $message');
    }
  }

  /// Log a warning. Printed in both debug and release modes.
  static void w(String message) {
    // ignore: avoid_print
    print('[$_tag:W] $message');
  }

  /// Log an error. Always printed. Optional [error] / [stack] for handlers.
  static void e(String message, {Object? error, StackTrace? stack}) {
    // ignore: avoid_print
    print('[$_tag:E] $message');
    if (error != null) {
      // ignore: avoid_print
      print('[$_tag:E]   Exception: $error');
    }
    if (stack != null && kDebugMode) {
      // ignore: avoid_print
      print('[$_tag:E]   Stack: $stack');
    }
  }
}
