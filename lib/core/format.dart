import 'jalali.dart';
import '../models/invoice.dart';

/// Number & money formatting helpers for the Persian UI.

const List<String> _faDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

/// Converts ASCII digits to Persian digits.
String toPersianDigits(String input) => input.replaceAllMapped(
    RegExp(r'[0-9]'), (m) => _faDigits[int.parse(m.group(0)!)]);

/// Converts Persian (۰-۹) and Arabic-Indic (٠-٩) digits to ASCII digits.
String toLatinDigits(String input) =>
    input.replaceAllMapped(RegExp(r'[\u06F0-\u06F9\u0660-\u0669]'), (m) {
      final c = m.group(0)!.runes.first;
      if (c >= 0x06F0 && c <= 0x06F9) return '${c - 0x06F0}';
      return '${c - 0x0660}';
    });

/// Inserts ASCII thousands separators: 1850000 -> "1,850,000".
String groupThousands(String digits) {
  final negative = digits.startsWith('-');
  final d = negative ? digits.substring(1) : digits;
  final sb = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    final remaining = d.length - i;
    sb.write(d[i]);
    if (remaining > 1 && remaining % 3 == 1) sb.write(',');
  }
  return negative ? '-$sb' : sb.toString();
}

const String faGroupSeparator = '٬';

/// Persian grouping: "1٬850٬000".
String groupThousandsFa(String digits) =>
    groupThousands(digits).replaceAll(',', faGroupSeparator);

/// Full money text: 1850000 => "۱٬۸۵۰٬۰۰۰ تومان".
String moneyText(int amount, String unit) =>
    '${toPersianDigits(groupThousandsFa('$amount'))} $unit';

/// Quantity text: 12 => "۱۲ عدد".
String qtyText(int qty) => '${toPersianDigits('$qty')} عدد';

/// Plain number in Persian digits.
String faNumber(int n) => toPersianDigits('$n');

/// Parses user input that may contain Persian/Arabic digits and separators.
/// Throws [FormatException] for invalid input.
int parseUserInt(String raw) {
  var s = toLatinDigits(raw).trim();
  if (s.isEmpty) throw const FormatException('empty');
  s = s.replaceAll(RegExp(r'[٬,،\s\u200f\u200e]'), '');
  return int.parse(s);
}

/// Parses user input; empty or invalid input returns null.
int? tryParseUserInt(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  try {
    return parseUserInt(t);
  } on FormatException {
    return null;
  }
}

/// Short Jalali date: "۱۴۰۵/۰۸/۱۵".
String faDateShort(DateTime dt) {
  final j = jalaliFromDateTime(dt);
  return toPersianDigits(
      '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}');
}

/// Long Jalali date: "پنجشنبه ۱۵ آبان ۱۴۰۵".
String faDateLong(DateTime dt) {
  final j = jalaliFromDateTime(dt);
  final wd = weekdaysFa[dt.weekday - 1];
  return '$wd ${toPersianDigits('${j.day}')} ${jalaliMonths[j.month - 1]} ${toPersianDigits('${j.year}')}';
}

/// "HH:MM" in Persian digits.
String faTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return toPersianDigits('$h:$m');
}

/// ---- Store payment information (bank card) helpers ----
///
/// Card data is sensitive store-level configuration: it lives ONLY in the
/// settings table, is normalized to plain digits, and is never logged.

/// Maximum stored card-number digits — a generic sanity cap, not an
/// issuer-specific validation rule.
const int maxCardDigits = 19;

/// Normalizes card-number input to a pure ASCII-digit string: converts
/// Persian/Arabic digits, then strips spaces, dashes and every other
/// separator. The stored value is always this normalized form.
String normalizeCardNumber(String raw) {
  final digits = toLatinDigits(raw).replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length > maxCardDigits
      ? digits.substring(0, maxCardDigits)
      : digits;
}

/// Readable groups of four digits: "6037 9912 3456 7890"
/// (a trailing remainder group is kept when the length is not a multiple
/// of four).
String formatCardNumber(String digits) {
  final d = normalizeCardNumber(digits);
  final sb = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    sb.write(d[i]);
    if ((i + 1) % 4 == 0 && i != d.length - 1) sb.write(' ');
  }
  return sb.toString();
}

/// Masked display for glanceable UI: "6037 •••• •••• 7890".
/// Short inputs are returned as-is (nothing worth masking).
String maskCardNumber(String digits) {
  final d = normalizeCardNumber(digits);
  if (d.length <= 8) return d;
  final sb = StringBuffer(d.substring(0, 4));
  final mid = d.length - 8;
  for (var i = 0; i < mid; i++) {
    if (i % 4 == 0) sb.write(' ');
    sb.write('•');
  }
  sb
    ..write(' ')
    ..write(d.substring(d.length - 4));
  return sb.toString();
}

/// Whether the store payment-information block belongs on this invoice's
/// image: ONLY unpaid invoices, and only when at least one card field is
/// configured at store level. Paid invoices never carry card details —
/// the fact that the invoice is paid is sufficient.
bool showPaymentInfoOnInvoice(
  InvoiceStatus status,
  String cardNumber,
  String cardHolderName,
) =>
    status == InvoiceStatus.unpaid &&
    (cardNumber.trim().isNotEmpty || cardHolderName.trim().isNotEmpty);
