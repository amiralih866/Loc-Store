import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/jalali.dart';
import 'database.dart';

class BackupValidation {
  final bool valid;
  final String? reason;
  final int productCount;
  final int invoiceCount;
  final int customerCount;
  const BackupValidation._(
      this.valid, this.reason, this.productCount, this.invoiceCount,
      [this.customerCount = 0]);

  factory BackupValidation.ok(int products, int invoices, [int customers = 0]) =>
      BackupValidation._(true, null, products, invoices, customers);
  factory BackupValidation.bad(String reason) =>
      BackupValidation._(false, reason, 0, 0);
}

class InvalidBackupException implements Exception {
  final String reason;
  const InvalidBackupException(this.reason);
}

/// Backup = a validated copy of the SQLite file. Restore swaps the file
/// after validation, with a safety copy kept until the swap succeeds.
class BackupService {
  final AppDatabase _adb;
  BackupService(this._adb);

  Future<Directory> _tmpDir() => getTemporaryDirectory();

  /// Creates a consistent backup file and returns its path.
  Future<String> createBackup() async {
    await _adb.checkpoint();
    final tmp = await _tmpDir();
    final dir = Directory(p.join(tmp.path, 'backups'));
    await dir.create(recursive: true);

    final j = jalaliFromDateTime(DateTime.now());
    final mm = j.month.toString().padLeft(2, '0');
    final dd = j.day.toString().padLeft(2, '0');
    final name = 'locstore-backup-${j.year}-$mm-$dd.db';

    final dest = File(p.join(dir.path, name));
    await File(_adb.path).copy(dest.path);

    final check = await validateBackup(dest.path);
    if (!check.valid) {
      try {
        await dest.delete();
      } catch (_) {}
      throw InvalidBackupException(check.reason ?? 'فایل پشتیبان معتبر نیست');
    }
    return dest.path;
  }

  /// Validates a candidate backup file: SQLite header, required tables,
  /// quick integrity check. Returns counts for the confirmation dialog.
  Future<BackupValidation> validateBackup(String path) async {
    final f = File(path);
    if (!await f.exists()) return BackupValidation.bad('فایل یافت نشد.');
    if (await f.length() < 4096) {
      return BackupValidation.bad('فایل بسیار کوچک است و معتبر نیست.');
    }

    final raf = await f.open();
    try {
      final header = await raf.read(16);
      final headerStr = String.fromCharCodes(header.sublist(0, 15));
      if (headerStr != 'SQLite format 3') {
        return BackupValidation.bad('این فایل یک پایگاه‌داده معتبر نیست.');
      }
    } finally {
      await raf.close();
    }

    Database? probe;
    try {
      probe = await _adb.factory.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final tables = await probe.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      final names = tables.map((r) => r['name'] as String).toSet();
      const required = {
        'products', 'variants', 'invoices', 'invoice_items', 'settings',
      };
      if (!names.containsAll(required)) {
        return BackupValidation.bad('ساختار فایل پشتیبان معتبر نیست.');
      }
      final check = await probe.rawQuery('PRAGMA quick_check');
      if ((check.first['quick_check'] as String?) != 'ok') {
        return BackupValidation.bad('فایل پشتیبان آسیب‌دیده است.');
      }
      final pc = await probe.rawQuery('SELECT COUNT(*) AS c FROM products');
      final ic = await probe.rawQuery('SELECT COUNT(*) AS c FROM invoices');
      // Older backups (schema v1) may not have a customers table yet —
      // they remain valid; migration creates it after restore.
      var cc = 0;
      if (names.contains('customers')) {
        final c = await probe.rawQuery('SELECT COUNT(*) AS c FROM customers');
        cc = (c.first['c'] as int?) ?? 0;
      }
      return BackupValidation.ok(
        (pc.first['c'] as int?) ?? 0,
        (ic.first['c'] as int?) ?? 0,
        cc,
      );
    } catch (_) {
      return BackupValidation.bad('خواندن فایل پشتیبان ممکن نشد.');
    } finally {
      try {
        await probe?.close();
      } catch (_) {}
    }
  }

  /// Restores [pickedPath] over the current database. The caller must show
  /// a confirmation dialog before invoking this — it replaces all data.
  Future<void> restoreFrom(String pickedPath) async {
    final v = await validateBackup(pickedPath);
    if (!v.valid) throw InvalidBackupException(v.reason ?? 'فایل پشتیبان معتبر نیست');

    final tmp = await _tmpDir();

    // Stage a local copy — the picked path may disappear (SAF cache).
    final staged = File(p.join(tmp.path, 'restore_incoming.db'));
    await File(pickedPath).copy(staged.path);

    // Safety copy of the current database until the swap succeeds.
    final safety = File(p.join(tmp.path, 'pre_restore_safety.db'));
    final current = File(_adb.path);
    if (await current.exists()) {
      await current.copy(safety.path);
    }

    await _adb.checkpoint();
    await _adb.closeCurrent();
    try {
      for (final suffix in ['-wal', '-shm']) {
        final f = File('${_adb.path}$suffix');
        if (await f.exists()) await f.delete();
      }
      await staged.copy(_adb.path);
      await _adb.reattach();
    } catch (e) {
      try {
        if (await safety.exists()) {
          await safety.copy(_adb.path);
          await _adb.reattach();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Permanently deletes all business data (products, variants, invoices,
  /// items, customers) in one transaction, then compacts the file. App
  /// preferences (theme/currency/store info) are kept.
  Future<void> deleteAllData() async {
    await _adb.transaction((txn) async {
      await txn.delete('invoice_items');
      await txn.delete('invoices');
      await txn.delete('variants');
      await txn.delete('products');
      await txn.delete('customers');
    });
    try {
      await _adb.db.execute(
          "DELETE FROM sqlite_sequence WHERE name IN ('products','variants','invoices','invoice_items','customers')");
      await _adb.db.execute('VACUUM');
    } catch (_) {}
  }
}
