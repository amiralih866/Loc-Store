import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locstore/data/backup_service.dart';
import 'package:locstore/data/database.dart';
import 'package:locstore/data/invoice_repository.dart';
import 'package:locstore/data/customer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Data-preservation path for version upgrades: a backup produced by the
/// OLD (schema v1 — before customers existed) app must (a) pass validation
/// and (b) migrate cleanly to the current schema after a restore, so the
/// user's existing products/invoices survive the update.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('validateBackup accepts a v1 database file (no customers table yet)',
      () async {
    final factory = databaseFactoryFfi;
    final path =
        '${Directory.systemTemp.path}/locstore_v1bk_${DateTime.now().microsecondsSinceEpoch}.db';

    // Minimal v1-schema database, as shipped by the old app version.
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
        },
      ),
    );
    await old.insert('invoices', {
      'number': 1001,
      'customer_name': 'علی رضایی',
      'total': 750000,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await old.close();

    final adb = await AppDatabase.open(path: ':memory:', factory: factory);
    final service = BackupService(adb);

    final v = await service.validateBackup(path);
    expect(v.valid, isTrue, reason: v.reason ?? '');
    expect(v.invoiceCount, 1);
    expect(v.customerCount, 0, reason: 'v1 backups have no customers table');

    // Simulate the post-restore reopen: schema jumps v1 → v2 and the old
    // invoice names become real linked customers — data is preserved.
    final restored =
        await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    final customers = CustomerRepository(restored);
    final invoices = InvoiceRepository(restored);

    final all = await customers.listSummaries();
    expect(all.length, 1);
    expect(all.first.customer.name, 'علی رضایی');
    expect(all.first.invoiceCount, 1);
    expect(all.first.totalSpent, 750000);
    expect((await invoices.listInvoices()).length, 1);

    await restored.db.close();
    await adb.db.close();
    try {
      File(path).deleteSync();
    } catch (_) {}
  });
}
