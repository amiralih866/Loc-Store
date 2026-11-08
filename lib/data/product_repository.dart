import '../models/invoice.dart' show DuplicateVariantException;
import '../models/product.dart';
import 'database.dart';

/// All product & variant data access. Business rules that involve several
/// rows run inside transactions so the database never ends up inconsistent.
class ProductRepository {
  final AppDatabase _adb;
  ProductRepository(this._adb);

  Future<List<ProductSummary>> listSummaries({
    String? query,
    bool archived = false,
    int lowStockThreshold = 5,
  }) async {
    final like = '%${(query ?? '').trim()}%';
    final rows = await _adb.db.rawQuery('''
      SELECT p.*,
        (SELECT COALESCE(SUM(v.stock),0) FROM variants v WHERE v.product_id = p.id) AS total_stock,
        (SELECT COUNT(*) FROM variants v WHERE v.product_id = p.id) AS variant_count,
        (SELECT COUNT(*) FROM variants v WHERE v.product_id = p.id AND v.stock > 0 AND v.stock <= ?) AS low_count,
        (SELECT COUNT(*) FROM variants v WHERE v.product_id = p.id AND v.stock = 0) AS out_count,
        (SELECT COUNT(*) FROM invoice_items ii WHERE ii.product_id = p.id) AS usage_count
      FROM products p
      WHERE p.active = ? AND (p.name LIKE ? OR p.color LIKE ?)
      ORDER BY p.updated_at DESC
    ''', [lowStockThreshold, archived ? 0 : 1, like, like]);

    return rows.map((r) => ProductSummary(
          product: Product.fromMap(r),
          totalStock: (r['total_stock'] as int?) ?? 0,
          variantCount: (r['variant_count'] as int?) ?? 0,
          lowCount: (r['low_count'] as int?) ?? 0,
          outCount: (r['out_count'] as int?) ?? 0,
          usageCount: (r['usage_count'] as int?) ?? 0,
        )).toList();
  }

  Future<(Product, List<ProductVariant>)?> getFull(int id) async {
    final pr = await _adb.db.query('products',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (pr.isEmpty) return null;
    final vs = await _adb.db.query('variants',
        where: 'product_id = ?', whereArgs: [id], orderBy: 'id ASC');
    return (Product.fromMap(pr.first), vs.map(ProductVariant.fromMap).toList());
  }

  Future<int> createProduct({
    required String name,
    required String color,
    required int defaultPrice,
    String? imagePath,
    required List<VariantInput> variants,
  }) async {
    final now = DateTime.now();
    final product = Product(
      name: name.trim(),
      color: color.trim(),
      defaultPrice: defaultPrice,
      imagePath: imagePath,
      createdAt: now,
      updatedAt: now,
    );
    return _adb.transaction((txn) async {
      final id = await txn.insert('products', product.toMap());
      for (final v in variants) {
        await txn.insert('variants', {
          'product_id': id,
          'name': v.name.trim(),
          'price': v.customPrice,
          'stock': v.stock,
          'created_at': now.millisecondsSinceEpoch,
        });
      }
      return id;
    });
  }

  Future<void> updateProduct({
    required Product existing,
    required List<VariantInput> variants,
    Set<int> removedVariantIds = const {},
  }) async {
    final seen = <String>{};
    for (final v in variants) {
      final n = v.name.trim();
      if (!seen.add(n.toLowerCase())) {
        throw DuplicateVariantException(n);
      }
    }
    await _adb.transaction((txn) async {
      await txn.update('products', existing.toMap(),
          where: 'id = ?', whereArgs: [existing.id]);
      for (final v in variants) {
        if (v.id == null) {
          await txn.insert('variants', {
            'product_id': existing.id,
            'name': v.name.trim(),
            'price': v.customPrice,
            'stock': v.stock,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
        } else {
          final cnt = await txn.update(
            'variants',
            {'name': v.name.trim(), 'price': v.customPrice, 'stock': v.stock},
            where: 'id = ?',
            whereArgs: [v.id],
          );
          if (cnt == 0) {
            await txn.insert('variants', {
              'product_id': existing.id,
              'name': v.name.trim(),
              'price': v.customPrice,
              'stock': v.stock,
              'created_at': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
      }
      for (final rid in removedVariantIds) {
        await txn.delete('variants', where: 'id = ?', whereArgs: [rid]);
      }
    });
  }

  Future<void> setArchived(int id, bool archived) async {
    await _adb.db.update(
      'products',
      {'active': archived ? 0 : 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Number of historical invoice items that reference this product.
  Future<int> usageCount(int productId) async {
    final rows = await _adb.db.rawQuery(
        'SELECT COUNT(*) AS c FROM invoice_items WHERE product_id = ?',
        [productId]);
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Hard delete — only safe when no invoice references the product.
  /// Otherwise use [setArchived] to keep historical invoices readable.
  Future<void> deleteHard(int id) async {
    await _adb.transaction((txn) async {
      final rows = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM invoice_items WHERE product_id = ?',
          [id]);
      if (((rows.first['c'] as int?) ?? 0) > 0) {
        throw StateError('product is referenced by invoices — archive instead');
      }
      await txn.delete('variants', where: 'product_id = ?', whereArgs: [id]);
      await txn.delete('products', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Adjusts a variant stock to an absolute value (>= 0).
  Future<void> setVariantStock({required int variantId, required int stock}) async {
    assert(stock >= 0);
    await _adb.db.rawUpdate(
        'UPDATE variants SET stock = ? WHERE id = ?', [stock, variantId]);
  }

  Future<void> updateVariant({
    required int variantId,
    String? name,
    int? customPrice,
    bool clearPrice = false,
  }) async {
    final map = <String, Object?>{};
    if (name != null) map['name'] = name.trim();
    if (clearPrice) {
      map['price'] = null;
    } else if (customPrice != null) {
      map['price'] = customPrice;
    }
    if (map.isEmpty) return;
    await _adb.db.update('variants', map,
        where: 'id = ?', whereArgs: [variantId]);
  }

  Future<List<ProductVariant>> variantsOf(int productId) async {
    final vs = await _adb.db.query('variants',
        where: 'product_id = ?', whereArgs: [productId], orderBy: 'id ASC');
    return vs.map(ProductVariant.fromMap).toList();
  }

  Future<void> deleteVariant(int variantId) async {
    await _adb.db.delete('variants', where: 'id = ?', whereArgs: [variantId]);
  }

  /// Low-stock & out-of-stock rows across all active products.
  Future<List<VariantWithProduct>> lowStockVariants({
    required int threshold,
    int limit = 8,
  }) async {
    // NB: v.product_id MUST be selected (aliased) — the row mapper casts it
    // to int; leaving it out made the home screen fail with
    // "type 'Null' is not a subtype of type 'int'" exactly when a variant
    // fell at/below the low-stock threshold.
    final rows = await _adb.db.rawQuery('''
      SELECT v.id AS vid, v.product_id AS vpid, v.name AS vname,
             v.price AS vprice, v.stock AS vstock,
             v.created_at AS vcreated, p.*
      FROM variants v JOIN products p ON p.id = v.product_id
      WHERE p.active = 1 AND v.stock <= ?
      ORDER BY v.stock ASC
      LIMIT ?
    ''', [threshold, limit]);

    return rows.map((r) {
      final variant = ProductVariant(
        id: r['vid'] as int?,
        productId: (r['vpid'] as int?) ?? 0,
        name: r['vname'] as String,
        customPrice: r['vprice'] as int?,
        stock: (r['vstock'] as int?) ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r['vcreated'] as int),
      );
      return VariantWithProduct(
        variant: variant,
        product: Product.fromMap(r),
      );
    }).toList();
  }

  Future<int> totalStockSum() async {
    final rows = await _adb.db.rawQuery('''
      SELECT COALESCE(SUM(v.stock), 0) AS s
      FROM variants v JOIN products p ON p.id = v.product_id
      WHERE p.active = 1
    ''');
    return (rows.first['s'] as int?) ?? 0;
  }

  Future<int> activeProductCount() async {
    final rows = await _adb.db
        .rawQuery('SELECT COUNT(*) AS c FROM products WHERE active = 1');
    return (rows.first['c'] as int?) ?? 0;
  }
}
