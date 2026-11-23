import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../data/backup_service.dart';
import '../../services/share_service.dart';
import '../../state/app_state.dart';
import '../shell.dart';
import '../widgets/dialogs.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  void _showWorking(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _closeWorking() {
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    _showWorking('در حال تهیه نسخه پشتیبان…');
    try {
      final path = await Services.instance.backup.createBackup();
      _closeWorking();
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Theme.of(ctx).colorScheme.primary, size: 24),
                const SizedBox(width: 10),
                const Expanded(child: Text('نسخه پشتیبان آماده شد')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('فایل پشتیبان با موفقیت ساخته شد. با دکمه‌های زیر می‌توانید آن را ذخیره یا به اشتراک بگذارید.',
                    style: TextStyle(height: 1.8, fontSize: 14)),
                const SizedBox(height: 12),
                Text(
                  p.basename(path),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _saveToStorage(path);
                },
                icon: const Icon(Icons.save_alt_rounded, size: 19),
                label: const Text('ذخیره در حافظه'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await shareFile(path, text: 'نسخه پشتیبان LocStore');
                },
                icon: const Icon(Icons.share_rounded, size: 19),
                label: const Text('اشتراک‌گذاری'),
              ),
            ],
          ),
        );
      }
    } on InvalidBackupException catch (e) {
      _closeWorking();
      if (mounted) errorDialog(context, body: e.reason);
    } catch (e) {
      _closeWorking();
      if (mounted) {
        errorDialog(context,
            body: 'تهیه نسخه پشتیبان ممکن نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToStorage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final result = await FilePicker.platform.saveFile(
        fileName: p.basename(path),
        bytes: bytes,
      );
      if (mounted && result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فایل پشتیبان ذخیره شد ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        errorDialog(context, body: 'ذخیره فایل ممکن نشد. دوباره تلاش کنید.');
      }
    }
  }

  Future<void> _restore() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = picked?.files.single.path;
      if (path == null || !mounted) return;

      _showWorking('در حال بررسی فایل پشتیبان…');
      BackupValidation v;
      try {
        v = await Services.instance.backup.validateBackup(path);
      } catch (e) {
        _closeWorking();
        if (mounted) {
          errorDialog(context, body: 'خواندن فایل ممکن نشد. فایل معتبر نیست.');
        }
        return;
      }
      _closeWorking();

      if (!v.valid) {
        if (mounted) {
          errorDialog(context,
              title: 'فایل پشتیبان معتبر نیست',
              body: v.reason ?? 'این فایل قابل بازیابی نیست.');
        }
        return;
      }
      if (!mounted) return;

      final ok = await confirmDialog(
        context,
        title: 'بازیابی نسخه پشتیبان',
        body:
            'همه اطلاعات فعلی (${faNumber(v.productCount)} کالا و ${faNumber(v.invoiceCount)} فاکتور) با محتوای فایل پشتیبان جایگزین می‌شود.\n\nاین عملیات قابل بازگشت نیست. ادامه می‌دهید؟',
        destructive: true,
        confirmLabel: 'بازیابی می‌کنم',
        icon: Icons.restore_rounded,
      );
      if (!ok || !mounted) return;

      _showWorking('در حال بازیابی اطلاعات…');
      try {
        await Services.instance.backup.restoreFrom(path);
        _closeWorking();
        if (!mounted) return;
        final ctrl = context.read<AppSettingsController>();
        final messenger = ScaffoldMessenger.of(context);
        final nav = Navigator.of(context, rootNavigator: true);
        await ctrl.load();
        messenger.showSnackBar(
          const SnackBar(content: Text('اطلاعات با موفقیت بازیابی شد ✓')),
        );
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppShell()),
          (r) => false,
        );
      } catch (e) {
        _closeWorking();
        if (mounted) {
          errorDialog(context, body: 'بازیابی ممکن نشد. فایل را بررسی کنید.');
        }
      }
    } catch (e) {
      if (mounted) {
        errorDialog(context, body: 'انتخاب فایل ممکن نشد.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('پشتیبان‌گیری و بازیابی')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.cloud_download_rounded,
                        color: scheme.primary),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'تهیه نسخه پشتیبان',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'از تمام کالاها، موجودی‌ها و فاکتورها یک فایل پشتیبان ساخته می‌شود. فایل را در جایی امن (مثل حافظه گوشی دیگر یا تلگرام سیو) نگه دارید.',
                    style: TextStyle(
                        fontSize: 13, height: 1.9, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text('تهیه نسخه پشتیبان'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.restore_rounded,
                        color: scheme.onTertiaryContainer),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'بازیابی از فایل پشتیبان',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اطلاعات فعلی با محتوای فایل پشتیبان جایگزین می‌شود. فایل ابتدا اعتبارسنجی می‌شود و پیش از جایگزینی، تأیید شما گرفته می‌شود.',
                    style: TextStyle(
                        fontSize: 13, height: 1.9, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restore,
                    icon: const Icon(Icons.upload_file_rounded, size: 20),
                    label: const Text('انتخاب فایل و بازیابی'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
