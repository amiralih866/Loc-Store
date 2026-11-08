import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/image_store.dart';
import '../data/settings_repository.dart';

/// Holds all persisted preferences & store info; notifies the UI on change.
class AppSettingsController extends ChangeNotifier {
  AppSettingsController(this._settings, this._images);

  final SettingsRepository _settings;
  final ImageStore _images;

  String currencyUnit = 'toman';
  ThemeMode themeMode = ThemeMode.system;
  AppPalette palette = AppPalette.teal;
  int lowStockThreshold = 5;
  String storeName = '';
  String storePhone = '';
  String storeAddress = '';
  String? storeLogoPath;
  bool loaded = false;

  Future<void> load() async {
    currencyUnit = await _settings.getString(SettingsRepository.kCurrency, 'toman');

    final tm = await _settings.getString(SettingsRepository.kThemeMode, 'system');
    themeMode = switch (tm) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final pi = int.tryParse(
            await _settings.getString(SettingsRepository.kPalette, '0')) ??
        0;
    palette = AppPalette.values[pi.clamp(0, AppPalette.values.length - 1)];

    final ls =
        int.tryParse(await _settings.getString(SettingsRepository.kLowStock, '5')) ?? 5;
    lowStockThreshold = ls < 1 ? 1 : ls;

    storeName = await _settings.getString(SettingsRepository.kStoreName, '');
    storePhone = await _settings.getString(SettingsRepository.kStorePhone, '');
    storeAddress = await _settings.getString(SettingsRepository.kStoreAddress, '');
    final logo = await _settings.getString(SettingsRepository.kStoreLogo, '');
    storeLogoPath = logo.isEmpty ? null : logo;

    loaded = true;
    notifyListeners();
  }

  String get currencyLabel => currencyUnit == 'rial' ? 'ریال' : 'تومان';

  String money(int v) => moneyText(v, currencyLabel);

  Future<void> setCurrencyUnit(String v) async {
    currencyUnit = v;
    await _settings.setString(SettingsRepository.kCurrency, v);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _settings.setString(SettingsRepository.kThemeMode, m.name);
    notifyListeners();
  }

  Future<void> setPalette(AppPalette p) async {
    palette = p;
    await _settings.setString(
        SettingsRepository.kPalette, '${AppPalette.values.indexOf(p)}');
    notifyListeners();
  }

  Future<void> setLowStockThreshold(int v) async {
    lowStockThreshold = v < 1 ? 1 : v;
    await _settings.setString(SettingsRepository.kLowStock, '$lowStockThreshold');
    notifyListeners();
  }

  Future<void> setStoreInfo({
    required String name,
    required String phone,
    required String address,
    String? logoPath,
  }) async {
    storeName = name.trim();
    storePhone = phone.trim();
    storeAddress = address.trim();
    if (logoPath != null) {
      if (storeLogoPath != null && storeLogoPath != logoPath) {
        await _images.delete(storeLogoPath!);
      }
      storeLogoPath = logoPath.isEmpty ? null : logoPath;
    }
    await _settings.setString(SettingsRepository.kStoreName, storeName);
    await _settings.setString(SettingsRepository.kStorePhone, storePhone);
    await _settings.setString(SettingsRepository.kStoreAddress, storeAddress);
    await _settings.setString(SettingsRepository.kStoreLogo, storeLogoPath ?? '');
    notifyListeners();
  }
}
