import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/product_image.dart';
import '../widgets/stock_badge.dart';
import 'product_details_screen.dart';
import 'product_edit_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _query = '';
  String _filter = 'all'; // all | low | out | archived
  late Future<List<ProductSummary>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<List<ProductSummary>> _fetch() async {
    final ctrl = context.read<AppSettingsController>();
    final archived = _filter == 'archived';
    var list = await Services.instance.products.listSummaries(
      query: _query,
      archived: archived,
      lowStockThreshold: ctrl.lowStockThreshold,
    );
    if (_filter == 'low') {
      list = list.where((s) => s.lowCount > 0).toList();
    } else if (_filter == 'out') {
      list = list.where((s) => s.totalStock <= 0).toList();
    }
    return list;
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = _fetch());
  }

  Future<void> _openEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProductEditScreen()),
    );
    _refresh();
  }

  Future<void> _openDetails(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailsScreen(productId: id)),
    );
    _refresh();
  }

  Future<void> _restore(ProductSummary s) async {
    final ok = await confirmDialog(
      context,
      title: 'بازگردانی از بایگانی',
      body: '«${s.product.name}» دوباره به انبار فعال اضافه می‌شود.',
      confirmLabel: 'بازگردانی',
      icon: Icons.unarchive_rounded,
    );
    if (!ok) return;
    try {
      await Services.instance.products.setArchived(s.product.id!, false);
      _refresh();
    } catch (e) {
      if (mounted) errorDialog(context, body: friendlyDbError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final isArchived = _filter == 'archived';

    return Scaffold(
      appBar: AppBar(title: Text(isArchived ? 'بایگانی کالاها' : 'انبار')),
      floatingActionButton: isArchived
          ? null
          : FloatingActionButton.extended(
              onPressed: _openEditor,
              icon: const Icon(Icons.add_rounded),
              label: const Text('افزودن کالا'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              onChanged: (v) {
                _query = v;
                _refresh();
              },
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'جستجوی نام یا رنگ کالا…',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('all', 'همه'),
                  const SizedBox(width: 8),
                  _chip('low', 'کم‌موجودی'),
                  const SizedBox(width: 8),
                  _chip('out', 'ناموجود'),
                  const SizedBox(width: 8),
                  _chip('archived', 'بایگانی'),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ProductSummary>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'خطا در بارگذاری انبار',
                    subtitle: friendlyDbError(snap.error),
                    buttonLabel: 'تلاش دوباره',
                    onButton: _refresh,
                  );
                }
                final list = snap.data ?? const <ProductSummary>[];
                if (list.isEmpty) {
                  if (isArchived) {
                    return const EmptyState(
                      icon: Icons.archive_outlined,
                      title: 'کالایی بایگانی نشده است',
                      subtitle: 'کالاهایی که در فاکتورها استفاده شده‌اند، هنگام حذف به بایگانی منتقل می‌شوند.',
                    );
                  }
                  if (_query.isNotEmpty) {
                    return const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'نتیجه‌ای یافت نشد',
                      subtitle: 'عبارت دیگری را جستجو کنید.',
                    );
                  }
                  if (_filter == 'low') {
                    return const EmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'کالای کم‌موجودی ندارید',
                      subtitle: 'همه اقلام در وضعیت خوبی هستند.',
                    );
                  }
                  if (_filter == 'out') {
                    return const EmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'هیچ کالایی ناموجود نیست',
                      subtitle: 'انبار شما در وضعیت خوبی است.',
                    );
                  }
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'هنوز کالایی ثبت نشده است',
                    subtitle: 'اولین کالای خود را اضافه کنید تا موجودی و قیمت‌ها را مدیریت کنید.',
                    buttonLabel: 'افزودن کالا',
                    onButton: _openEditor,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    final f = _fetch();
                    setState(() => _future = f);
                    await f;
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final s = list[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          leading: ProductImage(
                            relativePath: s.product.imagePath,
                            name: s.product.name,
                            size: 56,
                            radius: 14,
                          ),
                          title: Text(
                            s.product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${s.product.color.isNotEmpty ? 'رنگ ${s.product.color} • ' : ''}'
                              '${faNumber(s.variantCount)} سایز',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          trailing: isArchived
                              ? IconButton(
                                  icon: const Icon(Icons.unarchive_rounded),
                                  tooltip: 'بازگردانی',
                                  onPressed: () => _restore(s),
                                )
                              : StockBadge(
                                  stock: s.totalStock,
                                  lowThreshold: ctrl.lowStockThreshold,
                                ),
                          onTap: () => _openDetails(s.product.id!),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _filter = value);
        _refresh();
      },
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
