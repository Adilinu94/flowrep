import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages the Android Foreground Service for BLE streaming (P0-5 / DoD 4.4).
///
/// Without a connected-device FGS, Android 15+ can kill BLE when the screen
/// locks. iOS keeps CBCentralManager active without an equivalent service.
///
/// All platform calls are guarded: missing plugins / non-Android hosts never
/// throw into the workout path.
class ForegroundServiceManager {
  bool _isRunning = false;
  bool _initialized = false;

  /// When true, skip real platform calls (unit tests).
  @visibleForTesting
  static bool debugSkipPlatform = false;

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;
    if (debugSkipPlatform) {
      _isRunning = true;
      return;
    }
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    try {
      _ensureInit();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'FlowRep aktiv',
          notificationText: 'Wiederholungen werden gezählt',
          callback: flowRepForegroundCallback,
          serviceTypes: const [
            ForegroundServiceTypes.connectedDevice,
          ],
        );
      }
      _isRunning = true;
    } catch (e) {
      // FGS unavailable or permission denied — continue without it.
      debugPrint('ForegroundServiceManager.start failed: $e');
      _isRunning = false;
    }
  }

  Future<void> stop() async {
    if (!_isRunning && !debugSkipPlatform) {
      // Still try stop if we believe the OS may have one running.
    }
    if (debugSkipPlatform) {
      _isRunning = false;
      return;
    }
    if (kIsWeb || !Platform.isAndroid) {
      _isRunning = false;
      return;
    }

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('ForegroundServiceManager.stop failed: $e');
    }
    _isRunning = false;
  }

  void _ensureInit() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'flowrep_ble_fg',
        channelName: 'FlowRep Training',
        channelDescription:
            'Hält die BLE-Verbindung aktiv während des Trainings.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }
}

/// Top-level callback required by flutter_foreground_task (entry-point).
@pragma('vm:entry-point')
void flowRepForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_FlowRepEmptyTaskHandler());
}

class _FlowRepEmptyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
