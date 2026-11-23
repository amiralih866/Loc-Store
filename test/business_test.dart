import 'package:flutter_test/flutter_test.dart';
import 'package:locstore/data/database.dart';
import 'package:locstore/data/invoice_repository.dart';
import 'package:locstore/data/product_repository.dart';
import 'package:locstore/models/invoice.dart';
import 'package:locstore/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Business-rule tests running against a real SQLite engine (FFI) so the
/// transactional behaviour is verified end-to-end.
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

  Future<(int, List<ProductVariant>)> seed() async {
    final id = await products.createProduct(
      name: 'تیشرت ساده',
      color: 'مشکی',
      defaultPrice: 500000,
      variants: [
        const VariantInput(name: 'M', stock: 20),
        const VariantInput(name: 'L', customPrice: 550000, stock: 15),
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
        unitPrice: resolveUnitPrice(
          productDefault: 500000,
          variantCustom: v.customPrice,
        ),
        availableStock: v.stock,
      );

  test('pricing rule: variant custom price wins, else product default', () {
    expect(resolveUnitPrice(productDefault: 500000, variantCustom: null), 500000);
    expect(resolveUnitPrice(productDefault: 500000, variantCustom: 550000), 550000);
  });

  test('invoice creation decreases stock atomically and snapshots prices',
      () async {
    final (id, vs) = await seed();
    final inv = await invoices.createInvoice(
      customerName: 'علی رضایی',
      items: [draft(id, vs[0], 3)],
    );

    expect(inv.number, 1001);
    expect(inv.total, 1500000);
    expect(inv.items.single.unitPrice, 500000);
    expect(inv.items.single.productName, 'تیشرت ساده');

    final after = await products.variantsOf(id);
    expect(after[0].stock, 17); // 20 - 3
    expect(after[1].stock, 15); // untouched
  });

  test('invoice numbers increment', () async {
    final (id, vs) = await seed();
    final a = await invoices.createInvoice(
        customerName: 'a', items: [draft(id, vs[0], 1)]);
    final b = await invoices.createInvoice(
        customerName: 'b', items: [draft(id, vs[1], 2)]);
    expect(b.number, a.number + 1);
    expect(b.total, 1100000); // 2 × 550000
  });

  test('insufficient stock rejected — nothing written (transaction rollback)',
      () async {
    final (id, vs) = await seed();
    await expectLater(
      invoices.createInvoice(
          customerName: 'x', items: [draft(id, vs[0], 50)]),
      throwsA(isA<InsufficientStockException>()),
    );

    final rows = await adb.db.rawQuery('SELECT COUNT(*) AS c FROM invoices');
    expect(rows.first['c'], 0);
    final after = await products.variantsOf(id);
    expect(after[0].stock, 20);
  });

  test('price snapshot is immune to later price changes (critical rule)',
      () async {
    final (id, vs) = await seed();
    final inv = await invoices.createInvoice(
        customerName: 'علی', items: [draft(id, vs[0], 2)]);

    // Later the user raises prices: product 700000, variant custom 750000.
    final p = (await products.getFull(id))!.$1;
    await products.updateProduct(
      existing: p.copyWith(defaultPrice: 700000),
      variants: [
        VariantInput(id: vs[0].id, name: 'M', customPrice: 750000, stock: 18),
        VariantInput(id: vs[1].id, name: 'L', customPrice: 550000, stock: 15),
      ],
    );

    final re = await invoices.getInvoice(inv.id!);
    expect(re!.items.single.unitPrice, 500000); // historical snapshot
    expect(re.items.single.variantName, 'M');
    expect(re.total, 1000000);
  });

  test('deleting an invoice restocks items', () async {
    final (id, vs) = await seed();
    final inv = await invoices.createInvoice(
        customerName: 'علی', items: [draft(id, vs[0], 3)]);

    await invoices.deleteInvoice(inv.id!);

    final after = await products.variantsOf(id);
    expect(after[0].stock, 20);
    final rows = await adb.db.rawQuery('SELECT COUNT(*) AS c FROM invoices');
    expect(rows.first['c'], 0);
    final items =
        await adb.db.rawQuery('SELECT COUNT(*) AS c FROM invoice_items');
    expect(items.first['c'], 0);
  });

  test('used products cannot be hard-deleted; archive keeps history readable',
      () async {
    final (id, vs) = await seed();
    final inv = await invoices.createInvoice(
        customerName: 'علی', items: [draft(id, vs[0], 2)]);

    expect(await products.usageCount(id), 1);
    await expectLater(products.deleteHard(id), throwsA(isA<StateError>()));

    await products.setArchived(id, true);
    final re = await invoices.getInvoice(inv.id!);
    expect(re, isNotNull);
    expect(re!.items.single.productName, 'تیشرت ساده');

    final archived = await products.listSummaries(archived: true);
    expect(archived.any((s) => s.product.id == id), isTrue);
  });

  test('duplicate variant names rejected on update', () async {
    final (id, vs) = await seed();
    final p = (await products.getFull(id))!.$1;
    await expectLater(
      products.updateProduct(
        existing: p,
        variants: [
          VariantInput(id: vs[0].id, name: 'M', stock: 5),
          VariantInput(id: vs[1].id, name: 'm', stock: 5),
        ],
      ),
      throwsA(isA<DuplicateVariantException>()),
    );
  });
}
