/// Maps technical BLE errors to user-facing German messages (P2-4).
class BleErrorMapper {
  /// Returns a user-friendly error message for [error].
  static String toUserMessage(Object error) {
    final msg = error.toString().toLowerCase();

    if (msg.contains('bluetooth ist nicht aktiv') ||
        msg.contains('adapterstate') ||
        msg.contains('bluetooth_off') ||
        msg.contains('poweredoff')) {
      return 'Bluetooth ist ausgeschaltet. '
          'Bitte Bluetooth in den Einstellungen aktivieren.';
    }

    if (msg.contains('nicht gefunden') ||
        msg.contains('timeout') ||
        msg.contains('not found')) {
      return 'FlowRep-Sensor nicht gefunden. '
          'Stick eingeschaltet und in der Nähe? '
          '(BLE-Name: FlowRep oder GymTracker)';
    }

    if (msg.contains('mtu')) {
      return 'Verbindungsproblem (MTU). '
          'Bitte erneut versuchen.';
    }

    if (msg.contains('permission') || msg.contains('berechtigung')) {
      return 'Bluetooth-Berechtigung fehlt. '
          'Bitte in den App-Einstellungen erlauben.';
    }

    if (msg.contains('already connected') || msg.contains('busy')) {
      return 'Das Gerät ist bereits verbunden oder beschäftigt. '
          'Bitte kurz warten und erneut versuchen.';
    }

    return 'Verbindungsfehler. Bitte erneut versuchen.';
  }
}
