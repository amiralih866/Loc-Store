import 'format.dart';

/// Form validation helpers — all messages are user-friendly Persian texts.

String? validateRequired(String? v, String message) =>
    (v == null || v.trim().isEmpty) ? message : null;

String? validateMoneyField(
  String? v, {
  bool required = true,
  String emptyMessage = 'قیمت را وارد کنید',
  String invalidMessage = 'عدد معتبر وارد کنید',
}) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return required ? emptyMessage : null;
  final n = tryParseUserInt(t);
  if (n == null || n < 0) return invalidMessage;
  return null;
}

String? validateQtyField(String? v, {bool required = true}) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return required ? 'مقدار را وارد کنید' : null;
  final n = tryParseUserInt(t);
  if (n == null || n < 0) return 'عدد معتبر وارد کنید';
  return null;
}
