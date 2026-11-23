import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../models/invoice.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../inventory/product_details_screen.dart';
import '../invoices/create_invoice_screen.dart';
import '../invoices/invoice_details_screen.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/invoice_status_chip.dart';
import '../widgets/money_text.dart';
import '../widgets/product_image.dart';
import '../widgets/section_title.dart';
import '../widgets/stat_card.dart';
import '../widgets/stock_badge.dart';

class _HomeData {
  final int productCount;
  final int totalStock;
  final int todayCount;
  final int todaySales;
  final List<VariantWithProduct> lowStock;
  final List<Invoice> recent;

  const _HomeData({
    required this.productCount,
    required this.totalStock,
    required this.todayCount,
    required this.todaySales,
    required this.lowStock,
    required this.recent,
  });
}

class HomeScreen extends StatefulWidget {
  final ValueChanged<int> onGoTab;

  const HomeScreen({super.key, required this.onGoTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final s = Services.instance;
    final ctrl = context.read<AppSettingsController>();
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final productCount = await s.products.activeProductCount();
    final totalStock = await s.products.totalStockSum();
    final stats = await s.invoices.statsSince(startOfDay);
    final lowStock = await s.products.lowStockVariants(
      threshold: ctrl.lowStockThreshold,
      limit: 6,
    );
    final recent = await s.invoices.recent(limit: 4);

    return _HomeData(
      productCount: productCount,
      totalStock: totalStock,
      todayCount: stats.$1,
      todaySales: stats.$2,
      lowStock: lowStock,
      recent: recent,
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'صبح بخیر 👋';
    if (h < 15) return 'وقت بخیر 👋';
    if (h < 20) return 'عصر بخیر 👋';
    return 'شب بخیر 👋';
  }

  Future<void> _openCreate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateInvoiceScreen()),
    );
    _refresh();
  }

  Future<void> _openDetails(int productId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailsScreen(productId: productId)),
    );
    _refresh();
  }

  Future<void> _openInvoice(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailsScreen(invoiceId: id)),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        top: true,
        child: FutureBuilder<_HomeData>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'خطا در بارگذاری اطلاعات',
                subtitle: friendlyDbError(snap.error),
                buttonLabel: 'تلاش دوباره',
                onButton: _refresh,
              );
            }
            final data = snap.data;
            return RefreshIndicator(
              onRefresh: () async {
                final f = _load();
                setState(() => _future = f);
                await f;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Text(
                    _greeting(),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    faDateLong(DateTime.now()),
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _openCreate,
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('ثبت فاکتور جدید'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (data == null)
                    const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.55,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      children: [
                        StatCard(
                          icon: Icons.category_rounded,
                          value: faNumber(data.productCount),
                          label: 'کالا',
                        ),
                        StatCard(
                          icon: Icons.inventory_2_rounded,
                          value: '${faNumber(data.totalStock)} عدد',
                          label: 'موجودی انبار',
                        ),
                        StatCard(
                          icon: Icons.receipt_long_rounded,
                          value: faNumber(data.todayCount),
                          label: 'فاکتور امروز',
                          tint: scheme.tertiary,
                        ),
                        StatCard(
                          icon: Icons.payments_rounded,
                          value: ctrl.money(data.todaySales),
                          label: 'فروش امروز',
                          tint: scheme.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    SectionTitle('کم‌موجودی'),
                    const SizedBox(height: 12),
                    _lowStockSection(data, ctrl),
                    const SizedBox(height: 30),
                    SectionTitle(
                      'فاکتورهای اخیر',
                      actionLabel: data.recent.isEmpty ? null : 'مشاهده همه',
                      onAction: () => widget.onGoTab(3),
                    ),
                    const SizedBox(height: 12),
                    _recentSection(data, ctrl),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _lowStockSection(_HomeData data, AppSettingsController ctrl) {
    if (data.lowStock.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'همه اقلام موجود است — انبار در وضعیت خوبی است',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < data.lowStock.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
            ListTile(
              leading: ProductImage(
                relativePath: data.lowStock[i].product.imagePath,
                name: data.lowStock[i].product.name,
                size: 44,
                radius: 12,
              ),
              title: Text(
                data.lowStock[i].product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${data.lowStock[i].product.color.isNotEmpty ? '${data.lowStock[i].product.color} • ' : ''}'
                'سایز ${data.lowStock[i].variant.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
              trailing: StockBadge(
                stock: data.lowStock[i].variant.stock,
                lowThreshold: ctrl.lowStockThreshold,
                showQtyWhenLow: false,
              ),
              onTap: () => _openDetails(data.lowStock[i].product.id!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recentSection(_HomeData data, AppSettingsController ctrl) {
    if (data.recent.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'هنوز فاکتوری صادر نشده است',
        subtitle: 'اولین فاکتور خود را ثبت کنید.',
        buttonLabel: 'ثبت فاکتور',
        onButton: _openCreate,
        compact: true,
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < data.recent.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
            ListTile(
              leading: InvoiceNumberAvatar(number: data.recent[i].number),
              title: Text(
                data.recent[i].customerName.isEmpty
                    ? 'مشتری ناشناس'
                    : data.recent[i].customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${faNumber(data.recent[i].itemCount)} قلم • ${faTime(data.recent[i].createdAt)}',
                style: const TextStyle(fontSize: 12.5),
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    data.recent[i].total,
                    ctrl.currencyLabel,
                    fontSize: 14,
                  ),
                  const SizedBox(height: 4),
                  InvoiceStatusChip(
    status: data.recent[i].status,
                    fontSize: 10.5,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                  ),
                ],
              ),
              onTap: () => _openInvoice(data.recent[i].id!),
            ),
          ],
        ],
      ),
    );
  }
}
