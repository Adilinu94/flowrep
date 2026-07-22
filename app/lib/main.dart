import 'package:flutter/material.dart';

import 'presentation/screens/exercise_selection_screen.dart';

/// Entry point.
void main() {
  runApp(const FlowRepApp());
}

class FlowRepApp extends StatelessWidget {
  const FlowRepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlowRep',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const ExerciseSelectionScreen(),
    );
  }
}
