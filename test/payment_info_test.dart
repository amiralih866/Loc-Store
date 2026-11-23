import 'package:flutter_test/flutter_test.dart';
import 'package:locstore/core/format.dart';
import 'package:locstore/data/database.dart';
import 'package:locstore/data/image_store.dart';
import 'package:locstore/data/settings_repository.dart';
import 'package:locstore/models/invoice.dart';
import 'package:locstore/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Store payment-information feature (v1.3.0):
///  • card-number normalization / grouping / masking
///  • the unpaid-only visibility rule for the invoice image section
///  • store-level persistence through AppSettingsController (SQLite
///    settings rows — never copied onto invoices, never logged)
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('card number normalization & formatting', () {
    test('strips separators, keeps digits only', () {
      expect(normalizeCardNumber('6037-9912-3456-7890'), '6037991234567890');
      expect(normalizeCardNumber(' 6037 9912 3456 7890 '),
          '6037991234567890');
      expect(normalizeCardNumber('card: 6037abc9912!'), '60379912');
    });

    test('accepts Persian / Arabic digits', () {
      expect(normalizeCardNumber('۶۰۳۷۹۹۱۲۳۴۵۶۷۸۹۰'), '6037991234567890');
      expect(normalizeCardNumber('٦٠٣٧٩٩١٢٣٤٥٦٧٨٩٠'), '6037991234567890');
    });

    test('caps at the generic 19-digit limit', () {
      expect(
        normalizeCardNumber('1234567890123456789012345'),
        '1234567890123456789',
      );
    });

    test('formats in groups of four', () {
      expect(formatCardNumber('6037991234567890'), '6037 9912 3456 7890');
      expect(
        formatCardNumber('6037991234567890123'),
        '6037 9912 3456 7890 123',
      );
      expect(formatCardNumber('60379'), '6037 9');
      expect(formatCardNumber(''), '');
    });

    test('formatting is idempotent (safe to prefill the field)', () {
      final once = formatCardNumber('6037991234567890');
      expect(formatCardNumber(once), once);
    });

    test('masking keeps head & tail only', () {
      expect(maskCardNumber('6037991234567890'), '6037 •••• •••• 7890');
      expect(maskCardNumber('6037'), '6037');
      expect(maskCardNumber(''), '');
    });
  });

  group('payment info visibility rule (invoice image)', () {
    test('paid invoices never show card details', () {
      expect(
        showPaymentInfoOnInvoice(
            InvoiceStatus.paid, '6037991234567890', 'Amir Ahmadi'),
        isFalse,
      );
    });

    test('unpaid + card configured → show', () {
      expect(
        showPaymentInfoOnInvoice(InvoiceStatus.unpaid, '6037991234567890', ''),
        isTrue,
      );
    });

    test('unpaid + only holder configured → show (only that field)', () {
      expect(
        showPaymentInfoOnInvoice(InvoiceStatus.unpaid, '', 'Amir Ahmadi'),
        isTrue,
      );
    });

    test('unpaid + nothing configured → omit the whole section', () {
      expect(showPaymentInfoOnInvoice(InvoiceStatus.unpaid, '', ''), isFalse);
      expect(
        showPaymentInfoOnInvoice(InvoiceStatus.unpaid, '   ', '  '),
        isFalse,
      );
    });
  });

  group('store-level persistence (settings table, not invoices)', () {
    late AppDatabase adb;
    late SettingsRepository repo;

    setUp(() async {
      adb = await AppDatabase.open(
          path: ':memory:', factory: databaseFactoryFfi);
      repo = SettingsRepository(adb);
    });

    tearDown(() async {
      await adb.db.close();
    });

    test('setPaymentInfo normalizes, persists and round-trips via load()',
        () async {
      final ctrl = AppSettingsController(repo, const ImageStore());
      await ctrl.setPaymentInfo(
        cardNumber: '6037-9912-3456-7890',
        holderName: ' امیر احمدی ',
      );
      expect(ctrl.cardNumber, '6037991234567890');
      expect(ctrl.cardHolderName, 'امیر احمدی');

      // A fresh controller (like the next app launch) reads the same rows.
      final ctrl2 = AppSettingsController(repo, const ImageStore());
      await ctrl2.load();
      expect(ctrl2.cardNumber, '6037991234567890');
      expect(ctrl2.cardHolderName, 'امیر احمدی');
    });

    test('clearing: empty values erase both optional fields', () async {
      final ctrl = AppSettingsController(repo, const ImageStore());
      await ctrl.setPaymentInfo(
          cardNumber: '6037991234567890', holderName: 'امیر');
      await ctrl.setPaymentInfo(cardNumber: '', holderName: '');

      final ctrl2 = AppSettingsController(repo, const ImageStore());
      await ctrl2.load();
      expect(ctrl2.cardNumber, '');
      expect(ctrl2.cardHolderName, '');
    });

    test('card data lives in settings rows only — no invoice schema change',
        () async {
      final ctrl = AppSettingsController(repo, const ImageStore());
      await ctrl.setPaymentInfo(
          cardNumber: '6037991234567890', holderName: 'امیر');

      final rows = await adb.db
          .query('settings', where: '`key` LIKE ?', whereArgs: ['store_card%']);
      expect(rows.length, 2);
      final keys = rows.map((r) => r['key']).toSet();
      expect(
        keys,
        {SettingsRepository.kCardNumber, SettingsRepository.kCardHolderName},
      );
      // The values are the normalized digits + trimmed holder name.
      final map = {for (final r in rows) r['key'] as String: r['value']};
      expect(map[SettingsRepository.kCardNumber], '6037991234567890');
      expect(map[SettingsRepository.kCardHolderName], 'امیر');
    });
  });
}
