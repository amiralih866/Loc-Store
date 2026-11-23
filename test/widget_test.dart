import 'package:flutter_test/flutter_test.dart';
import 'package:locstore/core/format.dart';

/// Lightweight smoke test — full business rules live in business_test.dart.
void main() {
  test('app sanity: money + digits helpers', () {
    expect(moneyText(1850000, 'تومان'), '۱٬۸۵۰٬۰۰۰ تومان');
    expect(faNumber(1024), '۱۰۲۴');
    expect(tryParseUserInt('۵۵۰٬۰۰۰'), 550000);
  });
}
