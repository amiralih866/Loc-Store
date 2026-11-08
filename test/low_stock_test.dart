import 'package:flutter_test/flutter_test.dart';
import 'package:locstore/data/database.dart';
import 'package:locstore/data/product_repository.dart';
import 'package:locstore/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression test for the home-screen crash reported as
/// «خطا در بارگذاری اطلاعات» whenever a product's quantity fell below the
/// low-stock threshold.
///
/// Root cause: `lowStockVariants` selected `v.id, v.name, v.price, v.stock,
/// v.created_at, p.*` but never `v.product_id`, while the row mapper cast
/// `row['product_id'] as int` — a null cast error on the very first row.
/// With an empty low-stock list the mapper never ran, which is why the home
/// screen only broke once something actually became low/out of stock.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late AppDatabase adb;
  late ProductRepository products;

  setUp(() async {
    adb = await AppDatabase.open(path: ':memory:', factory: databaseFactoryFfi);
    products = ProductRepository(adb);
  });

  tearDown(() async {
    await adb.db.close();
  });

  test('lowStockVariants maps rows safely when variants are at/below threshold',
      () async {
    final pid = await products.createProduct(
      name: 'شلوار جین',
      color: 'آبی',
      defaultPrice: 900000,
      variants: const [
        VariantInput(name: 'M', stock: 12), // above threshold
        VariantInput(name: 'L', stock: 5), // exactly at threshold
        VariantInput(name: 'S', stock: 3), // below threshold
        VariantInput(name: 'XL', stock: 0), // out of stock
      ],
    );

    final low = await products.lowStockVariants(threshold: 5, limit: 8);

    expect(low, isNotEmpty);
    expect(low.length, 3, reason: 'stock <= threshold, ordered by stock ASC');

    // Ordered by stock ASC: XL(0), S(3), L(5).
    expect(low[0].variant.name, 'XL');
    expect(low[0].variant.stock, 0);
    expect(low[1].variant.name, 'S');
    expect(low[1].variant.stock, 3);
    expect(low[2].variant.name, 'L');
    expect(low[2].variant.stock, 5);

    // The previously-crashing mapping: product_id + full product round-trip.
    for (final row in low) {
      expect(row.variant.productId, pid);
      expect(row.product.id, pid);
      expect(row.product.name, 'شلوار جین');
      expect(row.product.color, 'آبی');
      expect(row.product.defaultPrice, 900000);
      expect(row.variant.customPrice, isNull);
    }

    // Higher-stock variants stay out of the list.
    final none = await products.lowStockVariants(threshold: 0, limit: 8);
    expect(none.map((r) => r.variant.name), isNot(contains('M')));
  });

  test('lowStockVariants respects limit and skips archived products', () async {
    final p1 = await products.createProduct(
      name: 'مانتو کوتاه',
      color: 'سرمه‌ای',
      defaultPrice: 1200000,
      variants: const [
        VariantInput(name: 'free', stock: 1),
      ],
    );
    final p2 = await products.createProduct(
      name: 'مانتو بلند',
      color: 'مشکی',
      defaultPrice: 1500000,
      variants: const [
        VariantInput(name: 'free', stock: 2),
      ],
    );
    await products.setArchived(p2, true);

    final low = await products.lowStockVariants(threshold: 5, limit: 8);
    expect(low.length, 1);
    expect(low.first.product.id, p1);
  });
}
