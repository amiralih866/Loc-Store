import 'package:flutter/material.dart';

import '../../core/format.dart';

/// Round − / + quantity stepper with the value in the middle.
class QtyStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const QtyStepper({
    super.key,
    required this.value,
    this.min = 0,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget btn(IconData icon, bool enabled, int delta) {
      return Material(
        color: enabled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onChanged(value + delta) : null,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 20,
              color: enabled
                  ? scheme.onPrimaryContainer
                  : scheme.outline,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove_rounded, value > min, -1),
        Container(
          width: 58,
          alignment: Alignment.center,
          child: Text(
            faNumber(value),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ),
        btn(Icons.add_rounded, value < max, 1),
      ],
    );
  }
}
