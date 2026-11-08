import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/qty_stepper.dart';
import 'backup_screen.dart';
import 'danger_zone_screen.dart';
import 'store_info_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _label(context, 'فروشگاه'),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.storefront_rounded),
              title: const Text('اطلاعات فروشگاه'),
              subtitle: Text(
                ctrl.storeName.isEmpty
                    ? 'نام و اطلاعات تماس برای فاکتورها'
                    : ctrl.storeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StoreInfoScreen()),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _label(context, 'ظاهر برنامه'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('پوسته رنگی',
                      style:
                          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final p in AppPalette.values) ...[
                        GestureDetector(
                          onTap: () => ctrl.setPalette(p),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: p.seed,
                              shape: BoxShape.circle,
                              border: ctrl.palette == p
                                  ? Border.all(
                                      color: scheme.onSurface, width: 2.5)
                                  : null,
                            ),
                            child: ctrl.palette == p
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 20)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('حالت نمایش',
                      style:
                          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined, size: 18),
                          label: Text('روشن')),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined, size: 18),
                          label: Text('تیره')),
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.settings_brightness_rounded, size: 18),
                          label: Text('خودکار')),
                    ],
                    selected: {ctrl.themeMode},
                    onSelectionChanged: (s) => ctrl.setThemeMode(s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _label(context, 'واحد پول'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'نحوه نمایش مبالغ — مقادیر ذخیره‌شده تغییر نمی‌کنند.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.7,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'toman', label: Text('تومان')),
                      ButtonSegment(value: 'rial', label: Text('ریال')),
                    ],
                    selected: {ctrl.currencyUnit},
                    onSelectionChanged: (s) => ctrl.setCurrencyUnit(s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _label(context, 'انبار'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('هشدار کم‌موجودی',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'موجودی کمتر یا مساوی این عدد، کم‌موجودی محسوب می‌شود.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.7,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  QtyStepper(
                    value: ctrl.lowStockThreshold,
                    min: 1,
                    max: 99,
                    onChanged: (n) => ctrl.setLowStockThreshold(n),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _label(context, 'پشتیبان‌گیری'),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.backup_rounded),
              title: const Text('پشتیبان‌گیری و بازیابی'),
              subtitle: const Text('تهیه نسخه پشتیبان یا بازیابی از فایل'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BackupScreen()),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _label(context, 'منطقه خطر', color: scheme.error),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            color: scheme.errorContainer.withValues(alpha: 0.25),
            child: ListTile(
              leading: Icon(Icons.delete_forever_rounded, color: scheme.error),
              title: Text('حذف همه اطلاعات',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: scheme.error)),
              subtitle: Text(
                'حذف دائمی کالاها، موجودی‌ها و فاکتورها',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              trailing: Icon(Icons.chevron_left_rounded, color: scheme.error),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DangerZoneScreen()),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('درباره',
                      style:
                          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('LocStore',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    'نسخه ۱٫۰٫۰ — مدیریت انبار و فاکتور پوشاک',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ساخته‌شده با Flutter و SQLite — کاملاً آفلاین و محلی',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text, {Color? color}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w800,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
