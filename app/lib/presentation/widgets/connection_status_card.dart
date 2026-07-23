import 'package:flutter/material.dart';

/// BLE-Verbindungsstatus-Karte (SPEC TEIL 6, §6.3).
class ConnectionStatusCard extends StatelessWidget {
  const ConnectionStatusCard({
    super.key,
    required this.statusText,
    required this.isConnected,
    this.batteryPercent,
    this.errorText,
    this.onConnect,
    this.onDisconnect,
  });

  final String statusText;
  final bool isConnected;
  final int? batteryPercent;
  final String? errorText;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: isConnected ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(statusText, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            if (batteryPercent != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    batteryPercent! > 20
                        ? Icons.battery_std
                        : Icons.battery_alert,
                    size: 18,
                    color: batteryPercent! > 20 ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text('Akku: $batteryPercent%'),
                ],
              ),
            ],
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            if (!isConnected && onConnect != null)
              ElevatedButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Gerät verbinden'),
              ),
            if (isConnected && onDisconnect != null)
              ElevatedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.bluetooth_disabled),
                label: const Text('Trennen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade100,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
