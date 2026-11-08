import 'package:flutter/material.dart';

import '../../models/invoice.dart';

/// Small colored pill for the invoice payment status — «پرداخت شده» (green)
/// or «پرداخت نشده» (amber). Used in the invoice list, invoice details,
/// customer invoice history, product sales history and the home screen so
/// the status is clearly visible everywhere.
class InvoiceStatusChip extends StatelessWidget {
  final InvoiceStatus status;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const InvoiceStatusChip({
    super.key,
    required this.status,
    this.fontSize = 11,
    this.padding =
        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
  });

  Color _fg(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return switch (status) {
      InvoiceStatus.paid =>
        dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      InvoiceStatus.unpaid =>
        dark ? const Color(0xFFFFB74D) : const Color(0xFFB45309),
    };
  }

  IconData get _icon => switch (status) {
        InvoiceStatus.paid => Icons.check_circle_rounded,
        InvoiceStatus.unpaid => Icons.schedule_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = _fg(scheme);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: fontSize + 3, color: fg),
          const SizedBox(width: 4),
          Text(
            status.faLabel,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
