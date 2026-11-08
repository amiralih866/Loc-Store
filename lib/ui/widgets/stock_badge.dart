import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/product.dart';

/// Stock status pill: «۱۲ عدد» / «کم‌موجودی» / «ناموجود».
class StockBadge extends StatelessWidget {
  final int stock;
  final int lowThreshold;
  final bool showQtyWhenLow;

  const StockBadge({
    super.key,
    required this.stock,
    required this.lowThreshold,
    this.showQtyWhenLow = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = stockStatusFor(stock, lowThreshold);

    final (Color bg, Color fg, String label) = switch (status) {
      StockStatus.out => (
          scheme.errorContainer.withValues(alpha: 0.65),
          scheme.onErrorContainer,
          'ناموجود',
        ),
      StockStatus.low => (
          scheme.tertiaryContainer.withValues(alpha: 0.55),
          scheme.onTertiaryContainer,
          showQtyWhenLow ? '${faNumber(stock)} عدد — کم‌موجودی' : 'کم‌موجودی',
        ),
      StockStatus.ok => (
          scheme.secondaryContainer.withValues(alpha: 0.45),
          scheme.onSecondaryContainer,
          '${faNumber(stock)} عدد',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
