/// Jalali (Shamsi) calendar conversions.
///
/// Faithful Dart port of the well-known `jalaali-js` algorithms
/// (Behrang Norouzinia, MIT). Uses truncating division and JS-style
/// remainder so results match the reference implementation exactly.
library;

const List<int> _breaks = [
  -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, //
  1635, 2060, 2097, 2192, 2262, 2394, 2455, 3178,
];

/// Truncating integer division (matches JS `~~(a/b)`).
int _tdiv(int a, int b) {
  var q = a ~/ b;
  if (a < 0 && a % b != 0) q += 1;
  return q;
}

/// JS-style remainder (can be negative, matches `%` in JS).
int _mod(int a, int b) => a - b * _tdiv(a, b);

class JalaliDate {
  final int year;
  final int month;
  final int day;

  const JalaliDate(this.year, this.month, this.day);

  @override
  bool operator ==(Object other) =>
      other is JalaliDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$year/$month/$day';
}

class _JalCal {
  final int leap; // 0 => leap year
  final int gy;
  final int march; // Gregorian day of March for Nowruz
  const _JalCal(this.leap, this.gy, this.march);
}

_JalCal _jalCal(int jy) {
  final bl = _breaks.length;
  final gy = jy + 621;
  var leapJ = -14;
  var jp = _breaks[0];
  var jump = 0;

  for (var i = 1; i < bl; i++) {
    final jm = _breaks[i];
    jump = jm - jp;
    if (jy < jm) break;
    leapJ += _tdiv(jump, 33) * 8 + _tdiv(_mod(jump, 33), 4);
    jp = jm;
  }
  var n = jy - jp;

  leapJ += _tdiv(n, 33) * 8 + _tdiv(_mod(n, 33) + 3, 4);
  if (_mod(jump, 33) == 4 && jump - n == 4) leapJ += 1;

  final leapG = _tdiv(gy, 4) - _tdiv((_tdiv(gy, 100) + 1) * 3, 4) - 150;
  final march = 20 + leapJ - leapG;

  if (jump - n < 6) n = n - jump + _tdiv(jump + 4, 33) * 33;
  var leap = _mod(_mod(n + 1, 33) - 1, 4);
  if (leap == -1) leap = 4;

  return _JalCal(leap, gy, march);
}

/// Gregorian date → Julian Day Number (Richards algorithm, exact).
int _g2d(int gy, int gm, int gd) {
  final a = _tdiv(14 - gm, 12);
  final y = gy + 4800 - a;
  final m = gm + 12 * a - 3;
  return gd +
      _tdiv(153 * m + 2, 5) +
      365 * y +
      _tdiv(y, 4) -
      _tdiv(y, 100) +
      _tdiv(y, 400) -
      32045;
}

class _GregDate {
  final int gy, gm, gd;
  const _GregDate(this.gy, this.gm, this.gd);
}

/// Julian Day Number → Gregorian date (Richards algorithm, exact).
_GregDate _d2g(int jdn) {
  final a = jdn + 32044;
  final b = _tdiv(4 * a + 3, 146097);
  final c = a - _tdiv(146097 * b, 4);
  final d = _tdiv(4 * c + 3, 1461);
  final e = c - _tdiv(1461 * d, 4);
  final m = _tdiv(5 * e + 2, 153);
  final gd = e - _tdiv(153 * m + 2, 5) + 1;
  final gm = m + 3 - 12 * _tdiv(m, 10);
  final gy = 100 * b + d - 4800 + _tdiv(m, 10);
  return _GregDate(gy, gm, gd);
}

int _j2d(int jy, int jm, int jd) {
  final r = _jalCal(jy);
  return _g2d(r.gy, 3, r.march) +
      (jm - 1) * 31 -
      _tdiv(jm, 7) * (jm - 7) +
      jd -
      1;
}

JalaliDate _d2j(int jdn) {
  final gy = _d2g(jdn).gy;
  var jy = gy - 621;
  final r = _jalCal(jy);
  final jdn1f = _g2d(gy, 3, r.march);
  var k = jdn - jdn1f;

  if (k >= 0) {
    if (k <= 185) {
      return JalaliDate(jy, 1 + _tdiv(k, 31), _mod(k, 31) + 1);
    }
    k -= 186;
  } else {
    jy -= 1;
    k += 179;
    if (r.leap == 1) k += 1;
  }
  return JalaliDate(jy, 7 + _tdiv(k, 30), _mod(k, 30) + 1);
}

/// Converts a Gregorian date to Jalali.
JalaliDate gregorianToJalali(int gy, int gm, int gd) => _d2j(_g2d(gy, gm, gd));

/// Converts a Jalali date to Gregorian.
JalaliDate jalaliToGregorian(int jy, int jm, int jd) {
  final g = _d2g(_j2d(jy, jm, jd));
  return JalaliDate(g.gy, g.gm, g.gd);
}

/// Whether a Jalali year is a leap year.
bool isJalaliLeap(int jy) => _jalCal(jy).leap == 0;

/// Number of days in a Jalali month.
int jalaliMonthLength(int jy, int jm) {
  if (jm <= 6) return 31;
  if (jm <= 11) return 30;
  return isJalaliLeap(jy) ? 30 : 29;
}

/// Converts a [DateTime] to a JalaliDate (uses the local calendar date).
JalaliDate jalaliFromDateTime(DateTime dt) =>
    gregorianToJalali(dt.year, dt.month, dt.day);

const List<String> jalaliMonths = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

/// Weekday names indexed by [DateTime.weekday] - 1 (Mon..Sun).
const List<String> weekdaysFa = [
  'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه',
];
