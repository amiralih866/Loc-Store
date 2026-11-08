import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'database.dart';

/// Simple key/value settings stored in the `settings` table.
class SettingsRepository {
  final AppDatabase _adb;
  SettingsRepository(this._adb);

  static const kCurrency = 'currency_unit'; // 'toman' | 'rial'
  static const kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const kPalette = 'palette'; // '0'..'3'
  static const kLowStock = 'low_stock_threshold';
  static const kStoreName = 'store_name';
  static const kStorePhone = 'store_phone';
  static const kStoreAddress = 'store_address';
  static const kStoreLogo = 'store_logo'; // relative image path

  Future<String> getString(String key, String fallback) async {
    final rows = await _adb.db.query('settings',
        where: '`key` = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return fallback;
    return (rows.first['value'] as String?) ?? fallback;
  }

  Future<void> setString(String key, String value) async {
    await _adb.db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
