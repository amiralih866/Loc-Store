import 'package:flutter_test/flutter_test.dart';
import 'package:locstore/core/format.dart';

void main() {
  test('money formatting: grouping + Persian digits', () {
    expect(moneyText(1850000, 'تومان'), '۱٬۸۵۰٬۰۰۰ تومان');
    expect(moneyText(0, 'تومان'), '۰ تومان');
    expect(moneyText(950000, 'ریال'), '۹۵۰٬۰۰۰ ریال');
    expect(faNumber(1024), '۱۰۲۴');
    expect(qtyText(12), '۱۲ عدد');
  });

  test('parses Persian & Latin digit input with separators', () {
    expect(tryParseUserInt('۵۵۰٬۰۰۰'), 550000);
    expect(tryParseUserInt('550,000'), 550000);
    expect(tryParseUserInt('۵۰۰'), 500);
    expect(tryParseUserInt('٥٠٠'), 500); // Arabic-Indic digits
    expect(tryParseUserInt('1 850 000'), 1850000);
    expect(tryParseUserInt('abc'), isNull);
    expect(tryParseUserInt(''), isNull);
    expect(tryParseUserInt(null), isNull);
  });

  test('round-trips digits', () {
    expect(toLatinDigits(toPersianDigits('1405/08/15')), '1405/08/15');
  });
}
