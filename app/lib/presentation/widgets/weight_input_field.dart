import 'package:flutter/material.dart';

/// Einfaches Zahlenfeld für das Gewicht (kg) des aktuellen/nächsten Satzes
/// (Bauplan Phase 3). Optional - leer lassen ist erlaubt, nicht jede Übung
/// braucht zwingend ein Gewicht (z. B. Bodyweight-Varianten).
///
/// Eigenes [StatefulWidget], damit der [TextEditingController] lokal lebt
/// (analog zu [StartCountdownButton], das aus dem gleichen Grund als
/// eigenes Widget ausgelagert wurde) - kein Cursor-Sprung beim Tippen durch
/// Riverpod-Rebuilds von außen.
class WeightInputField extends StatefulWidget {
  final double? initialWeightKg;
  final ValueChanged<double?> onChanged;

  const WeightInputField({
    super.key,
    required this.initialWeightKg,
    required this.onChanged,
  });

  @override
  State<WeightInputField> createState() => _WeightInputFieldState();
}

class _WeightInputFieldState extends State<WeightInputField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialWeightKg?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    // Komma UND Punkt als Dezimaltrenner erlauben (deutsche Tastatur).
    final normalized = value.trim().replaceAll(',', '.');
    widget.onChanged(normalized.isEmpty ? null : double.tryParse(normalized));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Gewicht (kg)',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: _handleChanged,
    );
  }
}
