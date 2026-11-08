import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

/// SQLite is the single source of truth for LocStore data.
///
/// [AppDatabase] wraps the raw database, owns the schema, and can be
/// re-attached after a backup restore (file replaced on disk).
class AppDatabase extends ChangeNotifier {
  AppDatabase._(this._db, this.path, this.factory);

  sqflite.Database _db;
  final String path;
  final sqflite.DatabaseFactory factory;

  sqflite.Database get db => _db;

  static const int schemaVersion = 3;

  static Future<AppDatabase> open({
    String? path,
    sqflite.DatabaseFactory? factory,
  }) async {
    final f = factory ?? sqflite.databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'locstore.db');
    final db = await f.openDatabase(
      dbPath,
      options: sqflite.OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (d) async {
          await d.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: _onOpen,
      ),
    );
    return AppDatabase._(db, dbPath, f);
  }

  static Future<void> _onOpen(sqflite.Database d) async {
    await d.execute('PRAGMA foreign_keys = ON');
    try {
      await d.execute('PRAGMA journal_mode = WAL');
    } catch (_) {
      // in-memory databases ignore WAL — safe to ignore
    }
  }

  static Future<void> _onCreate(sqflite.Database d, int version) async {
    final batch = d.batch();
    batch.execute('''
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
    batch.execute('''
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
    batch.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        number INTEGER NOT NULL UNIQUE,
        customer_id INTEGER REFERENCES customers(id),
        customer_name TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'Unpaid',
        description TEXT NOT NULL DEFAULT '',
        total INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    batch.execute('''
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
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_variants_product ON variants(product_id)');
    batch.execute('CREATE INDEX idx_items_invoice ON invoice_items(invoice_id)');
    batch.execute('CREATE INDEX idx_invoices_created ON invoices(created_at)');
    batch.execute('CREATE INDEX idx_customers_name ON customers(name)');
    batch.execute('CREATE INDEX idx_invoices_customer ON invoices(customer_id)');
    batch
        .insert('settings', {'key': 'schema_version', 'value': '$schemaVersion'});
    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(sqflite.Database d, int oldV, int newV) async {
    if (oldV < 2) await _migrateV1ToV2(d);
    if (oldV < 3) await _migrateV2ToV3(d);
  }

  /// v1 → v2: customers become real entities linked to invoices by id.
  ///
  /// Plain invoice name strings are promoted into customer rows (exact-name
  /// dedupe) and linked by customer_id, so existing history is preserved
  /// seamlessly and appears in the Customers section automatically.
  static Future<void> _migrateV1ToV2(sqflite.Database d) async {
    final batch = d.batch();
    batch.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_customers_name ON customers(name)');
    batch.execute(
        'ALTER TABLE invoices ADD COLUMN customer_id INTEGER REFERENCES customers(id)');
    batch.execute(
        'CREATE INDEX idx_invoices_customer ON invoices(customer_id)');
    batch.execute('''
      INSERT INTO customers (name, phone, notes, created_at)
      SELECT TRIM(customer_name), '', '', MIN(created_at)
      FROM invoices
      WHERE TRIM(customer_name) <> ''
      GROUP BY TRIM(customer_name)
    ''');
    batch.execute('''
      UPDATE invoices SET customer_id = (
        SELECT c.id FROM customers c
        WHERE c.name = TRIM(invoices.customer_name)
      )
      WHERE TRIM(customer_name) <> ''
    ''');
    batch.update('settings', {'value': '$schemaVersion'},
        where: 'key = ?', whereArgs: ['schema_version']);
    await batch.commit(noResult: true);
  }

  /// v2 → v3: invoices gain a payment status ('Paid' / 'Unpaid') and an
  /// optional free-text description.
  ///
  /// Existing invoices are upgraded IN PLACE: `ALTER TABLE ADD COLUMN` keeps
  /// every historical row untouched, with `Unpaid` / `''` as the defaults —
  /// exactly the values new invoices start with. No backup/restore round
  /// trip is needed; the user's data survives the app update automatically.
  static Future<void> _migrateV2ToV3(sqflite.Database d) async {
    final batch = d.batch();
    batch.execute(
        "ALTER TABLE invoices ADD COLUMN status TEXT NOT NULL DEFAULT 'Unpaid'");
    batch.execute(
        "ALTER TABLE invoices ADD COLUMN description TEXT NOT NULL DEFAULT ''");
    batch.update('settings', {'value': '$schemaVersion'},
        where: 'key = ?', whereArgs: ['schema_version']);
    await batch.commit(noResult: true);
  }

  /// Runs [action] inside a single SQLite transaction. Any thrown error
  /// rolls the whole transaction back — used for invoice/stock atomicity.
  Future<T> transaction<T>(
    Future<T> Function(sqflite.Transaction txn) action,
  ) =>
      _db.transaction(action);

  /// Flushes WAL into the main file so a plain file copy is a valid backup.
  Future<void> checkpoint() async {
    try {
      await _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  }

  /// Closes the current connection (before a restore swaps the file).
  Future<void> closeCurrent() => _db.close();

  /// Opens a fresh connection at [path] (after a restore replaced the file)
  /// and notifies all listeners so UI layers reload.
  Future<void> reattach({String? atPath}) async {
    final target = atPath ?? path;
    _db = await factory.openDatabase(
      target,
      options: sqflite.OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: false,
        onConfigure: (d) async {
          await d.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: _onOpen,
      ),
    );
    notifyListeners();
  }
}
