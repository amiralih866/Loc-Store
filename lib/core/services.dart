import 'package:sqflite/sqflite.dart' as sqflite;

import '../data/backup_service.dart';
import '../data/customer_repository.dart';
import '../data/database.dart';
import '../data/image_store.dart';
import '../data/invoice_repository.dart';
import '../data/product_repository.dart';
import '../data/settings_repository.dart';

/// Simple service locator — keeps UI widgets free of database wiring.
class Services {
  Services._();
  static final Services instance = Services._();

  late AppDatabase db;
  late ProductRepository products;
  late InvoiceRepository invoices;
  late CustomerRepository customers;
  late SettingsRepository settings;
  late ImageStore images;
  late BackupService backup;

  Future<void> init({
    String? dbPath,
    sqflite.DatabaseFactory? factory,
  }) async {
    db = await AppDatabase.open(path: dbPath, factory: factory);
    products = ProductRepository(db);
    invoices = InvoiceRepository(db);
    customers = CustomerRepository(db);
    settings = SettingsRepository(db);
    images = const ImageStore();
    backup = BackupService(db);
  }
}
