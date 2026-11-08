import '../core/format.dart';
import '../models/customer.dart';
import 'database.dart';

/// Customer data access.
///
/// - Names are NOT unique; [createOrGetByName] implements the inline-add
///   dedupe rule (exact trimmed match is reused, never duplicated).
/// - Summaries aggregate invoice data live (LEFT JOIN), so counts/totals
///   are always consistent with the invoices table.
class CustomerRepository {
  final AppDatabase _adb;
  CustomerRepository(this._adb);

  static const String _aggSelect = '''
    SELECT c.*,
      COUNT(i.id) AS invoice_count,
      COALESCE(SUM(i.total), 0) AS total_spent,
      MAX(i.created_at) AS last_invoice_at
    FROM customers c
    LEFT JOIN invoices i ON i.customer_id = c.id
  ''';

  CustomerSummary _summary(Map<String, Object?> r) => CustomerSummary(
        customer: Customer.fromMap(r),
        invoiceCount: (r['invoice_count'] as int?) ?? 0,
        totalSpent: (r['total_spent'] as int?) ?? 0,
        lastInvoiceAt: r['last_invoice_at'] as int?,
      );

  /// All customers with live aggregates — most recently active first,
  /// customers without invoices last.
  Future<List<CustomerSummary>> listSummaries({String? query}) async {
    final q = (query ?? '').trim();
    final rows = await _adb.db.rawQuery('''
      $_aggSelect
      WHERE (? = '' OR c.name LIKE ? OR c.phone LIKE ?)
      GROUP BY c.id
      ORDER BY (last_invoice_at IS NULL) ASC, last_invoice_at DESC, c.id DESC
    ''', [q, '%$q%', '%$q%']);
    return rows.map(_summary).toList();
  }

  /// Lightweight live suggestions for the invoice form. The search is
  /// primarily by name; typing digits also matches a phone number.
  Future<List<CustomerSummary>> suggestions(String query, {int limit = 6}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final phoneQ = toLatinDigits(q);
    final rows = await _adb.db.rawQuery('''
      $_aggSelect
      WHERE c.name LIKE ? OR (c.phone <> '' AND c.phone LIKE ?)
      GROUP BY c.id
      ORDER BY (last_invoice_at IS NULL) ASC, last_invoice_at DESC, c.id DESC
      LIMIT ?
    ''', ['%$q%', '%$phoneQ%', limit]);
    return rows.map(_summary).toList();
  }

  Future<Customer?> getById(int id) async {
    final rows = await _adb.db.query('customers',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<CustomerSummary?> getSummary(int id) async {
    final rows =
        await _adb.db.rawQuery('$_aggSelect WHERE c.id = ? GROUP BY c.id', [id]);
    return rows.isEmpty ? null : _summary(rows.first);
  }

  /// Exact (trimmed) name lookup — used to avoid duplicate customers.
  Future<Customer?> findExact(String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final rows = await _adb.db.query('customers',
        where: 'TRIM(name) = ?', whereArgs: [n], orderBy: 'id ASC', limit: 1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  /// Inline-add rule from the invoice form: reuse the existing customer on
  /// an exact name match, otherwise create a new one. Returns the customer
  /// and whether it was newly created.
  Future<(Customer, bool)> createOrGetByName(String name) async {
    final n = name.trim();
    final existing = await findExact(n);
    if (existing != null) return (existing, false);
    final now = DateTime.now();
    final id = await _adb.db.insert('customers', {
      'name': n,
      'phone': '',
      'notes': '',
      'created_at': now.millisecondsSinceEpoch,
    });
    return (Customer(id: id, name: n, createdAt: now), true);
  }

  /// Manual creation (Customers screen) — always inserts a new row; two
  /// people with the same name are legitimate separate customers.
  Future<int> create({
    required String name,
    String phone = '',
    String notes = '',
  }) async {
    final c = Customer(
      name: name.trim(),
      phone: phone.trim(),
      notes: notes.trim(),
      createdAt: DateTime.now(),
    );
    return _adb.db.insert('customers', c.toMap());
  }

  /// Updates profile fields only. Historical invoices keep their own name
  /// snapshot, so editing never rewrites old invoice records.
  Future<void> update(Customer c) async {
    await _adb.db.update(
      'customers',
      {
        'name': c.name.trim(),
        'phone': c.phone.trim(),
        'notes': c.notes.trim(),
      },
      where: 'id = ?',
      whereArgs: [c.id],
    );
  }

  /// Number of invoices referencing this customer.
  Future<int> invoiceCountOf(int id) async {
    final rows = await _adb.db.rawQuery(
        'SELECT COUNT(*) AS c FROM invoices WHERE customer_id = ?', [id]);
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Deletes a customer only when no invoices reference it — history must
  /// never break (there is no cascade delete for customers, ever).
  Future<void> delete(int id) async {
    final n = await invoiceCountOf(id);
    if (n > 0) throw CustomerHasInvoicesException(n);
    await _adb.db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }
}
