import 'package:flutter/material.dart';

import '../../core/format.dart';

/// Formatted money text (Persian digits + currency unit from settings).
class MoneyText extends StatelessWidget {
  final int value;
  final String unit;
  final double fontSize;
  final FontWeight weight;
  final Color? color;

  const MoneyText(
    this.value,
    this.unit, {
    super.key,
    this.fontSize = 14,
    this.weight = FontWeight.w700,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      moneyText(value, unit),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: weight,
        color: color ?? Theme.of(context).colorScheme.onSurface,
        height: 1.4,
      ),
    );
  }
}
