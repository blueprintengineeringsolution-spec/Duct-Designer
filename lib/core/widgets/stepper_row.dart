import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

class StepperRow extends StatelessWidget {
  final String label, value;
  final VoidCallback? onMinus, onPlus;
  const StepperRow({
    super.key,
    required this.label,
    required this.value,
    this.onMinus,
    this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label)),
        IconButton.filledTonal(
          tooltip: 'Decrease $label',
          onPressed: onMinus,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 96,
          child: Center(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Increase $label',
          onPressed: onPlus,
          icon: const Icon(Icons.add),
        ),
      ]),
    );
  }
}
