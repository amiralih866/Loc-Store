import 'package:flutter_test/flutter_test.dart';
import 'package:locstore/core/jalali.dart';

void main() {
  test('gregorian → jalali: known reference dates', () {
    expect(gregorianToJalali(2026, 3, 21), const JalaliDate(1405, 1, 1));
    expect(gregorianToJalali(2026, 11, 6), const JalaliDate(1405, 8, 15));
    // 1403 is a leap Jalali year → Esfand has 30 days
    expect(gregorianToJalali(2025, 3, 20), const JalaliDate(1403, 12, 30));
    // 1404 is not a leap year → Esfand has 29 days
    expect(gregorianToJalali(2026, 3, 20), const JalaliDate(1404, 12, 29));
  });

  test('jalali → gregorian round trip', () {
    final g = jalaliToGregorian(1405, 8, 15);
    expect(gregorianToJalali(g.year, g.month, g.day), const JalaliDate(1405, 8, 15));

    final g2 = jalaliToGregorian(1403, 12, 30);
    expect(gregorianToJalali(g2.year, g2.month, g2.day), const JalaliDate(1403, 12, 30));
  });

  test('month lengths & leap years', () {
    expect(jalaliMonthLength(1405, 1), 31);
    expect(jalaliMonthLength(1405, 7), 30);
    expect(jalaliMonthLength(1405, 12), 29);
    expect(jalaliMonthLength(1403, 12), 30);
    expect(isJalaliLeap(1403), isTrue);
    expect(isJalaliLeap(1404), isFalse);
    expect(isJalaliLeap(1408), isTrue);
  });

  test('day equality groups invoices by Persian calendar day', () {
    final a = jalaliFromDateTime(DateTime(2026, 11, 6, 9, 30));
    final b = jalaliFromDateTime(DateTime(2026, 11, 6, 22, 10));
    expect(a, b);
    expect(a, const JalaliDate(1405, 8, 15));
  });
}
