import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services.dart';
import '../shell.dart';
import '../widgets/dialogs.dart';

/// Delete-all-data flow — intentionally strict:
/// Step 1: full-screen warning with explicit Continue.
/// Step 2: type the exact phrase «DELETE ALL DATA» to unlock the button.
class DangerZoneScreen extends StatelessWidget {
  const DangerZoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('منطقه خطر')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.error.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.dangerous_rounded, color: scheme.error, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'حذف همه اطلاعات',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: scheme.error,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'همه کالاها، موجودی‌ها، مشتری‌ها و فاکتورها برای همیشه حذف می‌شوند.\n\nاین عملیات قابل بازگشت نیست و برنامه به حالت اولیه (خالی) بازمی‌گردد.',
                    style: TextStyle(fontSize: 13.5, height: 1.9),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.backup_rounded, color: scheme.primary, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'پیش از حذف، از اطلاعات خود نسخه پشتیبان تهیه کنید.',
                      style: TextStyle(fontSize: 13, height: 1.7),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'از صفحه تنظیمات ← پشتیبان‌گیری، نسخه پشتیبان تهیه کنید.')),
                      );
                    },
                    child: const Text('راهنما'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('انصراف'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const _ConfirmDeleteScreen()),
                    );
                  },
                  child: const Text('ادامه'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfirmDeleteScreen extends StatefulWidget {
  const _ConfirmDeleteScreen();

  @override
  State<_ConfirmDeleteScreen> createState() => _ConfirmDeleteScreenState();
}

class _ConfirmDeleteScreenState extends State<_ConfirmDeleteScreen> {
  String _phrase = '';

  bool get _unlocked => _phrase.trim() == 'DELETE ALL DATA';

  Future<void> _doDelete() async {
    final ok = await confirmDialog(
      context,
      title: 'حذف دائمی اطلاعات',
      body: 'آیا کاملاً مطمئن هستید؟ همه اطلاعات برای همیشه حذف می‌شود.',
      destructive: true,
      confirmLabel: 'بله، حذف کن',
      icon: Icons.delete_forever_rounded,
    );
    if (!ok || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('در حال حذف اطلاعات…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await Services.instance.backup.deleteAllData();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close working
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Theme.of(ctx).colorScheme.primary, size: 24),
              const SizedBox(width: 10),
              const Expanded(child: Text('همه اطلاعات حذف شد')),
            ],
          ),
          content: const Text(
            'برنامه به حالت اولیه بازگشت. حالا می‌توانید از نو شروع کنید.',
            style: TextStyle(height: 1.8, fontSize: 14),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx); // close dialog
                Navigator.of(ctx, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AppShell()),
                  (r) => false,
                );
              },
              child: const Text('بازگشت به خانه'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close working
      errorDialog(context,
          body: 'حذف اطلاعات ممکن نشد. دوباره تلاش کنید.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('حذف دائمی اطلاعات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            'برای تأیید حذف دائمی، عبارت زیر را دقیقاً تایپ کنید:',
            style: TextStyle(
                fontSize: 14.5, height: 1.8, color: scheme.onSurface),
          ),
          const SizedBox(height: 12),
          Card(
            color: scheme.errorContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SelectableText(
                  'DELETE ALL DATA',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: scheme.error,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => setState(() => _phrase = v),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.singleLineFormatter,
            ],
            decoration: const InputDecoration(
              hintText: 'عبارت تأیید را اینجا بنویسید',
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('انصراف'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _unlocked ? scheme.error : scheme.surfaceContainerHighest,
                    foregroundColor:
                        _unlocked ? scheme.onError : scheme.outline,
                  ),
                  onPressed: _unlocked ? _doDelete : null,
                  child: const Text('حذف دائمی'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'دکمه تا زمانی که عبارت دقیق تایپ نشود غیرفعال است. این محافظت برای جلوگیری از حذف تصادفی طراحی شده است.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, height: 1.8, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
