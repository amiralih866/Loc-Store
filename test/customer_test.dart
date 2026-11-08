import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locstore/data/customer_repository.dart';
import 'package:locstore/data/database.dart';
import 'package:locstore/data/invoice_repository.dart';
import 'package:locstore/data/product_repository.dart';
import 'package:locstore/models/customer.dart';
import 'package:locstore/models/invoice.dart';
import 'package:locstore/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Customer-management tests running against a real SQLite engine (FFI):
/// inline-add dedupe, invoice linking, live aggregates, deletion guard,
/// edit isolation and the v1 → v2 schema migration.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late AppDatabase adb;
  late CustomerRepository customers;
  late InvoiceRepository invoices;
  late ProductRepository products;

  setUp(() async {
    adb = await AppDatabase.open(path: ':memory:', factory: databaseFactoryFfi);
    customers = CustomerRepository(adb);
    invoices = InvoiceRepository(adb);
    products = ProductRepository(adb);
  });

  tearDown(() async {
    await adb.db.close();
  });

  Future<int> seedVariant() async {
    final pid = await products.createProduct(
      name: 'تیشرت ساده',
      color: 'مشکی',
      defaultPrice: 500000,
      variants: [const VariantInput(name: 'M', stock: 50)],
    );
    return (await products.variantsOf(pid)).first.id!;
  }

  InvoiceDraftItem draft(int variantId, int qty) => InvoiceDraftItem(
        variantId: variantId,
        productId: 0,
        productName: 'تیشرت ساده',
        productColor: 'مشکی',
        variantName: 'M',
        quantity: qty,
        unitPrice: 500000,
        availableStock: 50,
      );

  test('inline add: exact name match is reused, never duplicated', () async {
    final (c1, created1) = await customers.createOrGetByName('علی رضایی');
    final (c2, created2) = await customers.createOrGetByName(' علی رضایی ');

    expect(created1, isTrue);
    expect(created2, isFalse);
    expect(c2.id, c1.id);

    final all = await customers.listSummaries();
    expect(all.length, 1);
  });

  test('names are not unique: same name can exist as two customers', () async {
    await customers.create(name: 'علی رضایی', phone: '09120000000');
    await customers.create(name: 'علی رضایی', phone: '09350000000');

    final all = await customers.listSummaries();
    expect(all.length, 2);

    // Exact lookup returns a stable single row (first by id).
    final f = await customers.findExact('علی رضایی');
    expect(f, isNotNull);
    expect(f!.phone, '09120000000');
  });

  test('invoice stores customer id + historical name snapshot', () async {
    final vid = await seedVariant();
    final (c, _) = await customers.createOrGetByName('حسین محمدی');

    final inv = await invoices.createInvoice(
      customerName: c.name,
      customerId: c.id,
      items: [draft(vid, 2)],
    );

    expect(inv.customerId, c.id);
    expect(inv.customerName, 'حسین محمدی');

    final fetched = (await invoices.getInvoice(inv.id!))!;
    expect(fetched.customerId, c.id);

    final history = await invoices.listByCustomer(c.id!);
    expect(history.length, 1);
    expect(history.first.id, inv.id);
  });

  test('aggregates are computed live from invoice data, not counters',
      () async {
    final vid = await seedVariant();
    final (c, _) = await customers.createOrGetByName('علی احمدی');

    await invoices.createInvoice(
        customerName: c.name, customerId: c.id, items: [draft(vid, 3)]);
    await invoices.createInvoice(
        customerName: c.name, customerId: c.id, items: [draft(vid, 1)]);

    var s = await customers.getSummary(c.id!);
    expect(s!.invoiceCount, 2);
    expect(s.totalSpent, 2000000); // 3×500,000 + 1×500,000

    // Deleting an invoice automatically updates the aggregate.
    // (listByCustomer is newest-first, so this removes the qty-1 invoice.)
    final all = await invoices.listByCustomer(c.id!);
    await invoices.deleteInvoice(all.first.id!);

    s = await customers.getSummary(c.id!);
    expect(s!.invoiceCount, 1);
    expect(s.totalSpent, 1500000);
  });

  test('deleting a customer with invoices is prevented — history intact',
      () async {
    final vid = await seedVariant();
    final (c, _) = await customers.createOrGetByName('مریم کریمی');
    await invoices.createInvoice(
        customerName: c.name, customerId: c.id, items: [draft(vid, 1)]);

    await expectLater(
      customers.delete(c.id!),
      throwsA(isA<CustomerHasInvoicesException>()),
    );

    // Customer + invoice both survive.
    expect(await customers.getById(c.id!), isNotNull);
    expect((await invoices.listByCustomer(c.id!)).length, 1);
  });

  test('customer without invoices can be deleted', () async {
    final (c, created) = await customers.createOrGetByName('موقت');
    expect(created, isTrue);

    await customers.delete(c.id!);
    expect(await customers.getById(c.id!), isNull);
  });

  test('editing a customer never rewrites historical invoices', () async {
    final vid = await seedVariant();
    final (c, _) = await customers.createOrGetByName('نام قدیمی');

    final inv = await invoices.createInvoice(
        customerName: c.name, customerId: c.id, items: [draft(vid, 1)]);

    await customers.update(Customer(
      id: c.id,
      name: 'نام جدید',
      phone: '09121110000',
      notes: 'مشتری ویژه',
      createdAt: c.createdAt,
    ));

    // Snapshot on the invoice stays exactly as it was at sale time.
    final after = (await invoices.getInvoice(inv.id!))!;
    expect(after.customerName, 'نام قدیمی');
    expect(after.customerId, c.id);

    // Profile shows the new name, history still linked by id.
    final s = await customers.getSummary(c.id!);
    expect(s!.customer.name, 'نام جدید');
    expect(s.customer.phone, '09121110000');
    expect(s.invoiceCount, 1);
    expect(s.totalSpent, 500000);
  });

  test('suggestions search primarily by name, also by phone digits',
      () async {
    await customers.create(name: 'علی رضایی');
    await customers.create(name: 'علی احمدی');
    await customers.create(name: 'مریم کریمی', phone: '09121112233');

    expect((await customers.suggestions('علی')).length, 2);
    expect((await customers.suggestions('رضا')).length, 1);
    expect((await customers.suggestions('1122')).length, 1);
    expect(await customers.suggestions(''), isEmpty);
    expect(await customers.suggestions('وجود ندارد'), isEmpty);
  });

  test('v1 → v2 migration promotes invoice names into linked customers',
      () async {
    final factory = databaseFactoryFfi;
    final path =
        '${Directory.systemTemp.path}/locstore_migr_${DateTime.now().microsecondsSinceEpoch}.db';

    // Build the exact v1 schema (before customers existed).
    final old = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) async {
          await d.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              color TEXT NOT NULL DEFAULT '',
              default_price INTEGER NOT NULL DEFAULT 0,
              image_path TEXT,
              active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await d.execute('''
            CREATE TABLE variants (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
              name TEXT NOT NULL,
              price INTEGER,
              stock INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              UNIQUE(product_id, name)
            )
          ''');
          await d.execute('''
            CREATE TABLE invoices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              number INTEGER NOT NULL UNIQUE,
              customer_name TEXT NOT NULL DEFAULT '',
              total INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL
            )
          ''');
          await d.execute('''
            CREATE TABLE invoice_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
              product_id INTEGER,
              variant_id INTEGER,
              product_name TEXT NOT NULL,
              product_color TEXT NOT NULL DEFAULT '',
              variant_name TEXT NOT NULL DEFAULT '',
              quantity INTEGER NOT NULL,
              unit_price INTEGER NOT NULL,
              total INTEGER NOT NULL
            )
          ''');
          await d.execute(
              "CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
          await d.execute(
              "INSERT INTO settings (key, value) VALUES ('schema_version', '1')");
          await d.execute(
              'CREATE INDEX idx_variants_product ON variants(product_id)');
          await d.execute(
              'CREATE INDEX idx_items_invoice ON invoice_items(invoice_id)');
          await d.execute(
              'CREATE INDEX idx_invoices_created ON invoices(created_at)');
        },
      ),
    );

    final t = DateTime.now().millisecondsSinceEpoch;
    // Two invoices for علی رضایی, one for حسین محمدی, one anonymous.
    await old.insert('invoices', {
      'number': 1001,
      'customer_name': 'علی رضایی',
      'total': 750000,
      'created_at': t - 3000,
    });
    await old.insert('invoices', {
      'number': 1002,
      'customer_name': 'علی رضایی',
      'total': 1200000,
      'created_at': t - 2000,
    });
    await old.insert('invoices', {
      'number': 1003,
      'customer_name': 'حسین محمدی',
      'total': 900000,
      'created_at': t - 1000,
    });
    await old.insert('invoices', {
      'number': 1004,
      'customer_name': '',
      'total': 100000,
      'created_at': t,
    });
    await old.close();

    // Re-opening with the current schema triggers the migration.
    final upgraded =
        await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    final cr = CustomerRepository(upgraded);
    final ir = InvoiceRepository(upgraded);

    final all = await cr.listSummaries();
    expect(all.length, 2, reason: 'distinct non-empty names become customers');

    final ali = all.firstWhere((s) => s.customer.name == 'علی رضایی');
    expect(ali.invoiceCount, 2);
    expect(ali.totalSpent, 1950000);

    final linked = await ir.listByCustomer(ali.customer.id!);
    expect(linked.length, 2);

    final anonymous =
        await upgraded.db.rawQuery('SELECT COUNT(*) AS c FROM invoices '
            'WHERE customer_id IS NULL');
    expect(anonymous.first['c'], 1);

    // No duplicate customer rows were created for repeated names.
    final dupe = await upgraded.db.rawQuery(
        'SELECT COUNT(*) AS c FROM (SELECT name FROM customers GROUP BY name)');
    expect(dupe.first['c'], 2);

    await upgraded.db.close();
    try {
      File(path).deleteSync();
    } catch (_) {}
  });
}
