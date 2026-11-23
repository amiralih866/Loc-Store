import 'package:flutter/material.dart';

/// Standard confirmation / info / error dialogs (Material 3).

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'تأیید',
  String cancelLabel = 'انصراف',
  bool destructive = false,
  IconData? icon,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon,
                color: destructive ? scheme.error : scheme.primary, size: 24),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 17)),
          ),
        ],
      ),
      content: Text(
        body,
        style: TextStyle(
          height: 1.8,
          fontSize: 14,
          color: scheme.onSurfaceVariant,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

Future<void> infoDialog(
  BuildContext context, {
  required String title,
  required String body,
  String okLabel = 'متوجه شدم',
  IconData? icon,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Theme.of(ctx).colorScheme.primary, size: 24),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 17)),
          ),
        ],
      ),
      content: Text(
        body,
        style: TextStyle(
          height: 1.8,
          fontSize: 14,
          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(okLabel),
        ),
      ],
    ),
  );
}

Future<void> errorDialog(
  BuildContext context, {
  required String body,
  String title = 'خطا',
  IconData icon = Icons.error_outline_rounded,
}) {
  return infoDialog(
    context,
    title: title,
    body: body,
    icon: icon,
    okLabel: 'باشه',
  );
}

/// Friendly, non-technical message for unexpected failures.
String friendlyDbError(Object? e) =>
    'عملیات ممکن نشد. لطفاً اطلاعات وارد شده را بررسی کنید و دوباره تلاش کنید.';
