import 'package:flutter/widgets.dart';

/// Beobachtet App-Lifecycle-Änderungen (P1-2).
///
/// Wird vom [EngineNotifier] gehalten und in dispose() entfernt.
class AppLifecycleObserver with WidgetsBindingObserver {
  final void Function(AppLifecycleState state) onStateChanged;

  AppLifecycleObserver({required this.onStateChanged}) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
