import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locstore/data/database.dart';
import 'package:locstore/data/invoice_repository.dart';
import 'package:locstore/data/product_repository.dart';
import 'package:locstore/models/invoice.dart';
import 'package:locstore/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tests for the v1.2.0 invoice features: payment status (Paid/Unpaid),
/// optional description, the v2→v3 schema migration (data must survive an
/// app update untouched) and the per-variant sales history computed from
/// invoice-item data.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late AppDatabase adb;
  late ProductRepository products;
  late InvoiceRepository invoices;

  setUp(() async {
    adb = await AppDatabase.open(path: ':memory:', factory: databaseFactoryFfi);
    products = ProductRepository(adb);
    invoices = InvoiceRepository(adb);
  });

  tearDown(() async {
    await adb.db.close();
  });

  Future<(int, List<ProductVariant>)> seed3() async {
    final id = await products.createProduct(
      name: 'تیشرت ساده',
      color: 'مشکی',
      defaultPrice: 500000,
      variants: [
        const VariantInput(name: 'XL', stock: 30),
        const VariantInput(name: 'M', stock: 30),
        const VariantInput(name: 'S', stock: 30),
      ],
    );
    return (id, await products.variantsOf(id));
  }

  InvoiceDraftItem draft(int productId, ProductVariant v, int qty) =>
      InvoiceDraftItem(
        variantId: v.id!,
        productId: productId,
        productName: 'تیشرت ساده',
        productColor: 'مشکی',
        variantName: v.name,
        quantity: qty,
        unitPrice: 500000,
        availableStock: v.stock,
      );

  // ------------------------------------------------------------- status

  test('every new invoice defaults to Unpaid with an empty description',
      () async {
    final (id, vs) = await seed3();
    final inv = await invoices.createInvoice(
      customerName: 'علی رضایی',
      items: [draft(id, vs[0], 2)],
    );
    expect(inv.status, InvoiceStatus.unpaid);
    expect(inv.description, '');

    final re = (await invoices.getInvoice(inv.id!))!;
    expect(re.status, InvoiceStatus.unpaid);
    expect(re.description, '');
  });

  test('status and description chosen at creation are persisted', () async {
    final (id, vs) = await seed3();
    final inv = await invoices.createInvoice(
      customerName: 'مریم احمدی',
      items: [draft(id, vs[0], 1)],
      status: InvoiceStatus.paid,
      description: 'تحویل درب منزل\nتخفیف ۱۰ درصد',
    );
    final re = (await invoices.getInvoice(inv.id!))!;
    expect(re.status, InvoiceStatus.paid);
    expect(re.description, 'تحویل درب منزل\nتخفیف ۱۰ درصد');
  });

  test('status stays editable after creation (Invoice Details rule)',
      () async {
    final (id, vs) = await seed3();
    final inv = await invoices.createInvoice(
      customerName: 'رضا محمدی',
      items: [draft(id, vs[0], 1)],
    );
    // created unpaid → switched to paid → back to unpaid
    await invoices.updateInvoiceMeta(inv.id!, status: InvoiceStatus.paid);
    expect((await invoices.getInvoice(inv.id!))!.status, InvoiceStatus.paid);
    await invoices.updateInvoiceMeta(inv.id!, status: InvoiceStatus.unpaid);
    expect((await invoices.getInvoice(inv.id!))!.status,
        InvoiceStatus.unpaid);
  });

  test('description is editable later; clearing it removes the text',
      () async {
    final (id, vs) = await seed3();
    final inv = await invoices.createInvoice(
      customerName: 'سارا محمدی',
      items: [draft(id, vs[1], 1)],
    );
    await invoices.updateInvoiceMeta(inv.id!, description: 'ارسال با پست');
    expect((await invoices.getInvoice(inv.id!))!.description, 'ارسال با پست');
    await invoices.updateInvoiceMeta(inv.id!, description: '   ');
    expect((await invoices.getInvoice(inv.id!))!.description, '');
  });

  test('meta updates never touch the historical snapshots', () async {
    final (id, vs) = await seed3();
    final inv = await invoices.createInvoice(
      customerName: 'حسن احمدی',
      items: [draft(id, vs[0], 3)],
      status: InvoiceStatus.paid,
    );
    await invoices.updateInvoiceMeta(inv.id!,
        status: InvoiceStatus.unpaid, description: 'یادداشت');

    final re = (await invoices.getInvoice(inv.id!))!;
    expect(re.total, 1500000); // snapshot total untouched
    expect(re.items.single.quantity, 3);
    expect(re.items.single.unitPrice, 500000);
    expect(re.number, inv.number);
    expect(re.customerName, 'حسن احمدی');
  });

  test('unknown stored status values fall back to Unpaid', () {
    expect(InvoiceStatusX.parse(null), InvoiceStatus.unpaid);
    expect(InvoiceStatusX.parse('Whatever'), InvoiceStatus.unpaid);
    expect(InvoiceStatusX.parse('Paid'), InvoiceStatus.paid);
    expect(InvoiceStatusX.parse('Unpaid'), InvoiceStatus.unpaid);
  });

  // ------------------------------------------------- v2 → v3 migration

  test('v2 → v3 migration keeps all invoice data and defaults status',
      () async {
    final path =
        '${Directory.systemTemp.path}/locstore_v2_${DateTime.now().microsecondsSinceEpoch}.db';
    final factory = databaseFactoryFfi;

    // A database exactly as schema v2 (v1.1.1) produced it: invoices have
    // customer_id but NO status/description columns yet.
    final old = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
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
            CREATE TABLE customers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              phone TEXT NOT NULL DEFAULT '',
              notes TEXT NOT NULL DEFAULT '',
              created_at INTEGER NOT NULL
            )
          ''');
          await d.execute('''
            CREATE TABLE invoices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              number INTEGER NOT NULL UNIQUE,
              customer_id INTEGER REFERENCES customers(id),
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
              "INSERT INTO settings (key, value) VALUES ('schema_version', '2')");
        },
      ),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final custId = await old.insert('customers', {
      'name': 'علی رضایی',
      'phone': '0912',
      'notes': '',
      'created_at': now,
    });
    final invId = await old.insert('invoices', {
      'number': 1001,
      'customer_id': custId,
      'customer_name': 'علی رضایی',
      'total': 750000,
      'created_at': now,
    });
    await old.insert('invoice_items', {
      'invoice_id': invId,
      'product_id': 1,
      'variant_id': 1,
      'product_name': 'تیشرت ساده',
      'product_color': 'مشکی',
      'variant_name': 'XL',
      'quantity': 2,
      'unit_price': 375000,
      'total': 750000,
    });
    await old.close();

    // Re-open with the current schema — the app upgrade path. The old rows
    // must survive untouched and gain the defaults of a fresh invoice.
    final upgraded =
        await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    final repo = InvoiceRepository(upgraded);

    final inv = (await repo.getInvoice(invId))!;
    expect(inv.number, 1001);
    expect(inv.customerName, 'علی رضایی');
    expect(inv.customerId, custId); // customer link preserved
    expect(inv.total, 750000);
    expect(inv.status, InvoiceStatus.unpaid); // migration default
    expect(inv.description, ''); // migration default
    expect(inv.items.single.variantName, 'XL');
    expect(inv.items.single.quantity, 2);

    // And the migrated invoice is immediately editable like any new one.
    await repo.updateInvoiceMeta(invId, status: InvoiceStatus.paid);
    expect((await repo.getInvoice(invId))!.status, InvoiceStatus.paid);

    await upgraded.db.close();
    try {
      File(path).deleteSync();
    } catch (_) {}
  });

  // ------------------------------------------------ sales history

  test('sales history groups by variant with live totals from items',
      () async {
    final (id, vs) = await seed3(); // XL, M, S
    final xl = vs[0], m = vs[1], s = vs[2];

    final a = await invoices.createInvoice(
      customerName: 'علی رضایی',
      items: [draft(id, xl, 2)],
    ); // XL +2
    final b = await invoices.createInvoice(
      customerName: 'مریم احمدی',
      items: [draft(id, xl, 3), draft(id, m, 1)],
    ); // XL +3, M +1 (same invoice, two variants)
    final c = await invoices.createInvoice(
      customerName: 'رضا محمدی',
      items: [draft(id, xl, 7)],
    ); // XL +7
    final d2 = await invoices.createInvoice(
      customerName: 'حسن احمدی',
      items: [draft(id, m, 2), draft(id, s, 1)],
    ); // M +2, S +1
    final e = await invoices.createInvoice(
      customerName: 'سارا محمدی',
      items: [draft(id, m, 5), draft(id, s, 3)],
    ); // M +5, S +3

    final hist = await invoices.productSalesHistory(id);
    expect(hist.map((g) => g.variantName).toList(), ['XL', 'M', 'S']);

    // "XL — 12 sold" (2+3+7)
    expect(hist[0].totalSold, 12);
    expect(
      hist[0].entries.map((e) => e.invoiceNumber).toList(),
      [c.number, b.number, a.number], // newest first
    );
    expect(
      hist[0].entries.map((e) => e.customerName).toList(),
      ['رضا محمدی', 'مریم احمدی', 'علی رضایی'],
    );
    expect(
      hist[0].entries.map((e) => e.quantity).toList(),
      [7, 3, 2],
    );

    // "M — 8 sold" (1+2+5)
    expect(hist[1].totalSold, 8);
    expect(
      hist[1].entries.map((e) => e.customerName).toList(),
      ['سارا محمدی', 'حسن احمدی', 'مریم احمدی'],
    );

    // "S — 4 sold" (1+3)
    expect(hist[2].totalSold, 4);

    // every entry points at the real invoice
    final first = hist[0].entries.first;
    final inv = (await invoices.getInvoice(first.invoiceId))!;
    expect(inv.number, first.invoiceNumber);
    expect(inv.customerName, first.customerName);

    // sanity: timestamps never ascend inside a group (newest first)
    for (final g in hist) {
      for (var i = 1; i < g.entries.length; i++) {
        expect(
          g.entries[i - 1].createdAt.isBefore(g.entries[i].createdAt),
          isFalse,
          reason: 'entries of "${g.variantName}" must be newest-first',
        );
      }
    }

    // IDs used by tap-through exist for all entries
    final ids = [
      a.id!, b.id!, c.id!, d2.id!, e.id!,
    ];
    for (final g in hist) {
      for (final en in g.entries) {
        expect(ids.contains(en.invoiceId), isTrue);
      }
    }
  });

  test('history is live: deleting an invoice updates the totals', () async {
    final (id, vs) = await seed3();
    final inv = await invoices.createInvoice(
      customerName: 'علی رضایی',
      items: [draft(id, vs[0], 4)],
    );
    expect(
        (await invoices.productSalesHistory(id)).first.totalSold, 4);

    await invoices.deleteInvoice(inv.id!);
    expect(await invoices.productSalesHistory(id), isEmpty);
  });

  test('products without invoices have an empty history', () async {
    final (id, _) = await seed3();
    expect(await invoices.productSalesHistory(id), isEmpty);
  });

  test('other products never leak into this product\'s history',
      () async {
    final (id1, vs1) = await seed3();
    final id2 = await products.createProduct(
      name: 'پیراهن مردانه',
      color: 'آبی',
      defaultPrice: 900000,
      variants: [const VariantInput(name: 'XL', stock: 10)],
    );
    await invoices.createInvoice(
      customerName: 'علی رضایی',
      items: [draft(id1, vs1[0], 2)],
    );
    // a sale of a DIFFERENT product with the same variant name 'XL'
    final vs2 = await products.variantsOf(id2);
    await invoices.createInvoice(
      customerName: 'مریم احمدی',
      items: [
        InvoiceDraftItem(
          variantId: vs2[0].id!,
          productId: id2,
          productName: 'پیراهن مردانه',
          productColor: 'آبی',
          variantName: 'XL',
          quantity: 5,
          unitPrice: 900000,
          availableStock: 10,
        ),
      ],
    );

    final hist = await invoices.productSalesHistory(id1);
    expect(hist.single.totalSold, 2); // only product 1's XL
  });
}
