import 'jalali.dart';

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
