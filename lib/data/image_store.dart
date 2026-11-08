import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stores product photos & store logo in app documents storage and keeps
/// only a relative path reference in SQLite (spec: no big binaries in DB).
class ImageStore {
  const ImageStore();

  static Directory? _cachedDocs;

  /// Cached documents directory — lets widgets build image paths cheaply.
  static Future<Directory> docs() async {
    final cached = _cachedDocs;
    if (cached != null) return cached;
    final d = await getApplicationDocumentsDirectory();
    _cachedDocs = d;
    return d;
  }

  Future<Directory> _docsDir() => docs();

  Future<String> _save(XFile xfile, String subDir, String? replaceOld) async {
    final docs = await _docsDir();
    final dir = Directory(p.join(docs.path, subDir));
    await dir.create(recursive: true);
    final ext = p.extension(xfile.path).toLowerCase();
    final safeExt = (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp')
        ? ext
        : '.jpg';
    final name =
        '${subDir}_${DateTime.now().microsecondsSinceEpoch}$safeExt';
    await File(xfile.path).copy(p.join(dir.path, name));
    if (replaceOld != null && replaceOld.isNotEmpty) {
      await delete(replaceOld);
    }
    return '$subDir/$name';
  }

  Future<String?> saveProductImage(XFile xfile, {String? replaceOld}) =>
      _save(xfile, 'product_images', replaceOld);

  Future<String?> saveLogo(XFile xfile, {String? replaceOld}) =>
      _save(xfile, 'branding', replaceOld);

  Future<File> fileFor(String relativePath) async {
    final docs = await _docsDir();
    return File(p.join(docs.path, relativePath));
  }

  Future<void> delete(String relativePath) async {
    if (relativePath.isEmpty) return;
    try {
      final docs = await _docsDir();
      final f = File(p.join(docs.path, relativePath));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
