import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../models/invoice.dart';
import '../models/product.dart';
import 'database.dart';

/// Invoice data access — creation & deletion are transactional and keep
/// inventory in perfect sync (critical business rule).
class InvoiceRepository {
  final AppDatabase _adb;
  InvoiceRepository(this._adb);

  /// Creates an invoice and decreases stock as ONE atomic operation.
  ///
  /// - Validates stock for every item first (clear [InsufficientStockException]).
  /// - Snapshots product/variant names and the resolved unit price at sale
  ///   time so historical invoices never change when prices change later.
  /// - Stores the linked [customerId] plus a historical name snapshot.
  /// - Persists the selected payment [status] (default: Unpaid) and the
  ///   optional free-text [description].
  /// - Uses `UPDATE ... WHERE stock >= ?` as a final guard; if any update
  ///   touches 0 rows the transaction rolls back entirely.
  Future<Invoice> createInvoice({
    required String customerName,
    int? customerId,
    required List<InvoiceDraftItem> items,
    InvoiceStatus status = InvoiceStatus.unpaid,
    String description = '',
  }) async {
    if (items.isEmpty) throw const EmptyInvoiceException();

    return _adb.transaction((txn) async {
      final resolved = <(InvoiceDraftItem, String, String, String, int)>[];

      for (final it in items) {
        final vr = await txn.query('variants',
            where: 'id = ?', whereArgs: [it.variantId], limit: 1);
        if (vr.isEmpty) throw const VariantNotFoundException();
        final v = ProductVariant.fromMap(vr.first);

        final pr = await txn.query('products',
            where: 'id = ?', whereArgs: [v.productId], limit: 1);
        if (pr.isEmpty) throw const VariantNotFoundException();
        final prod = Product.fromMap(pr.first);

        final price = resolveUnitPrice(
            productDefault: prod.defaultPrice, variantCustom: v.customPrice);

        if (it.quantity > v.stock) {
          throw InsufficientStockException(
            productName: prod.name,
            variantName: v.name,
            available: v.stock,
          );
        }
        resolved.add((it, prod.name, prod.color, v.name, price));
      }

      final nRow =
          await txn.rawQuery('SELECT COALESCE(MAX(number), 1000) + 1 AS n FROM invoices');
      final number = (nRow.first['n'] as int?) ?? 1001;

      final now = DateTime.now().millisecondsSinceEpoch;
      final total = resolved.fold<int>(0, (s, r) => s + r.$1.quantity * r.$5);

      final invId = await txn.insert('invoices', {
        'number': number,
        'customer_id': customerId,
        'customer_name': customerName.trim(),
        'status': status.storage,
        'description': description.trim(),
        'total': total,
        'created_at': now,
      });

      for (final r in resolved) {
        final it = r.$1;
        await txn.insert('invoice_items', {
          'invoice_id': invId,
          'product_id': it.productId,
          'variant_id': it.variantId,
          'product_name': r.$2,
          'product_color': r.$3,
          'variant_name': r.$4,
          'quantity': it.quantity,
          'unit_price': r.$5,
          'total': it.quantity * r.$5,
        });
        final updated = await txn.rawUpdate(
          'UPDATE variants SET stock = stock - ? WHERE id = ? AND stock >= ?',
          [it.quantity, it.variantId, it.quantity],
        );
        if (updated != 1) throw const VariantNotFoundException();
      }

      return (await _getTx(txn, invId))!;
    });
  }

  Future<Invoice?> _getTx(DatabaseExecutor exec, int id) async {
    final rows = await exec.query('invoices',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final invoice = Invoice.fromMap(rows.first);
    final items = await exec.query('invoice_items',
        where: 'invoice_id = ?', whereArgs: [id], orderBy: 'id ASC');
    return Invoice(
      id: invoice.id,
      number: invoice.number,
      customerId: invoice.customerId,
      customerName: invoice.customerName,
      total: invoice.total,
      createdAt: invoice.createdAt,
      status: invoice.status,
      description: invoice.description,
      itemCount: items.length,
      items: items.map(InvoiceItem.fromMap).toList(),
    );
  }

  Future<Invoice?> getInvoice(int id) => _getTx(_adb.db, id);

  /// Updates only the mutable meta fields of an invoice — payment status
  /// and/or the free-text description. Historical snapshots (items, prices,
  /// names, totals) are never touched by this method.
  Future<void> updateInvoiceMeta(
    int id, {
    InvoiceStatus? status,
    String? description,
  }) async {
    if (status == null && description == null) return;
    final map = <String, Object?>{};
    if (status != null) map['status'] = status.storage;
    if (description != null) map['description'] = description.trim();
    await _adb.db
        .update('invoices', map, where: 'id = ?', whereArgs: [id]);
  }

  /// Sales history of one product, organized by variant/type.
  ///
  /// Computed purely from `invoice_items` joined to `invoices` — the sold
  /// quantities are never stored as a counter on the product. Each invoice
  /// that contains several variants of this product contributes one entry
  /// to every corresponding group. Groups are ordered by total sold (most
  /// first), entries within a group by invoice date (newest first).
  Future<List<VariantSalesGroup>> productSalesHistory(int productId) async {
    final rows = await _adb.db.rawQuery('''
      SELECT ii.variant_id AS vid,
             ii.variant_name AS vname,
             ii.quantity AS qty,
             i.id AS iid,
             i.number AS inum,
             i.customer_name AS cname,
             i.status AS istatus,
             i.created_at AS icreated
      FROM invoice_items ii
      JOIN invoices i ON i.id = ii.invoice_id
      WHERE ii.product_id = ?
      ORDER BY i.created_at DESC, ii.id DESC
    ''', [productId]);

    final groups = <String, VariantSalesGroup>{};
    final totals = <String, int>{};
    for (final r in rows) {
      final vid = r['vid'] as int?;
      final vname = (r['vname'] as String?) ?? '';
      // Group by the variant id when available; fall back to the snapshot
      // name for very old rows without an id.
      final key = vid != null ? 'v$vid' : 'n$vname';
      // The newest row of the group provides the display name, so a variant
      // that was renamed later shows its most recent name.
      groups.putIfAbsent(
        key,
        () => VariantSalesGroup(
          variantName: vname.isEmpty ? '—' : vname,
          totalSold: 0,
          entries: [],
        ),
      );
      totals[key] = (totals[key] ?? 0) + ((r['qty'] as int?) ?? 0);
      groups[key]!.entries.add(VariantSaleEntry(
        invoiceId: r['iid'] as int,
        invoiceNumber: r['inum'] as int,
        customerName: ((r['cname'] as String?) ?? '').trim(),
        quantity: (r['qty'] as int?) ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r['icreated'] as int),
        status: InvoiceStatusX.parse(r['istatus']),
      ));
    }
    final result = groups.values.toList();
    for (var i = 0; i < result.length; i++) {
      final key = groups.keys.elementAt(i);
      result[i] = VariantSalesGroup(
        variantName: result[i].variantName,
        totalSold: totals[key] ?? 0,
        entries: result[i].entries,
      );
    }
    result.sort((a, b) => b.totalSold.compareTo(a.totalSold));
    return result;
  }

  /// Deletes an invoice and returns every item quantity back to stock
  /// (variants deleted since the sale are simply skipped — snapshots keep
  /// the historical record intact, but there is nothing to restock).
  Future<void> deleteInvoice(int invoiceId) async {
    await _adb.transaction((txn) async {
      final items = await txn.query('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoiceId]);
      for (final it in items) {
        final vid = it['variant_id'] as int?;
        final qty = (it['quantity'] as int?) ?? 0;
        if (vid != null && qty > 0) {
          await txn.rawUpdate(
              'UPDATE variants SET stock = stock + ? WHERE id = ?', [qty, vid]);
        }
      }
      await txn.delete('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoiceId]);
      await txn.delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);
    });
  }

  Future<List<Invoice>> listInvoices({
    String? query,
    int limit = 200,
    int offset = 0,
  }) async {
    final q = (query ?? '').trim();
    final rows = await _adb.db.rawQuery('''
      SELECT i.*, (SELECT COUNT(*) FROM invoice_items it WHERE it.invoice_id = i.id) AS item_count
      FROM invoices i
      WHERE (? = '' OR i.customer_name LIKE ? OR CAST(i.number AS TEXT) LIKE ?)
      ORDER BY i.created_at DESC
      LIMIT ? OFFSET ?
    ''', ['%$q%', '%$q%', '%${toLatinDigits(q)}%', limit, offset]);
    return rows.map(Invoice.fromMap).toList();
  }

  Future<List<Invoice>> recent({int limit = 5}) async {
    final rows = await _adb.db.rawQuery('''
      SELECT i.*, (SELECT COUNT(*) FROM invoice_items it WHERE it.invoice_id = i.id) AS item_count
      FROM invoices i
      ORDER BY i.created_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(Invoice.fromMap).toList();
  }

  /// (invoice count, sales sum) for invoices created at/after [startOfDay].
  Future<(int, int)> statsSince(DateTime startOfDay) async {
    final rows = await _adb.db.rawQuery(
      'SELECT COUNT(*) AS c, COALESCE(SUM(total),0) AS s FROM invoices WHERE created_at >= ?',
      [startOfDay.millisecondsSinceEpoch],
    );
    return (
      (rows.first['c'] as int?) ?? 0,
      (rows.first['s'] as int?) ?? 0,
    );
  }

  /// All invoices of one customer — newest first. Aggregates for the
  /// customer profile are computed from invoice data (never counters).
  Future<List<Invoice>> listByCustomer(int customerId, {int limit = 500}) async {
    final rows = await _adb.db.rawQuery('''
      SELECT i.*,
        (SELECT COUNT(*) FROM invoice_items it WHERE it.invoice_id = i.id) AS item_count
      FROM invoices i
      WHERE i.customer_id = ?
      ORDER BY i.created_at DESC
      LIMIT ?
    ''', [customerId, limit]);
    return rows.map(Invoice.fromMap).toList();
  }

  /// (invoice count, total purchase amount) for one customer, computed
  /// live from the invoices table.
  Future<(int, int)> statsForCustomer(int customerId) async {
    final rows = await _adb.db.rawQuery(
      'SELECT COUNT(*) AS c, COALESCE(SUM(total),0) AS s FROM invoices WHERE customer_id = ?',
      [customerId],
    );
    return (
      (rows.first['c'] as int?) ?? 0,
      (rows.first['s'] as int?) ?? 0,
    );
  }
}
