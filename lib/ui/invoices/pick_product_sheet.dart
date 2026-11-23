import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/product_image.dart';

/// First step of adding a product to an invoice: pick a product.
/// Returns the selected [ProductSummary] via Navigator.pop.
class ProductPickerSheet extends StatefulWidget {
  const ProductPickerSheet({super.key});

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  String _query = '';
  late Future<List<ProductSummary>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = Services.instance.products.listSummaries(
        query: _query,
        lowStockThreshold:
            context.read<AppSettingsController>().lowStockThreshold,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'انتخاب کالا',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            autofocus: false,
            onChanged: (v) {
              _query = v;
              _refresh();
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'جستجوی کالا…',
              isDense: true,
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
              final list = snap.data ?? const <ProductSummary>[];
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: _query.isEmpty ? 'کالایی ثبت نشده است' : 'نتیجه‌ای یافت نشد',
                  subtitle: _query.isEmpty
                      ? 'اول از انبار یک کالا اضافه کنید.'
                      : 'عبارت دیگری را جستجو کنید.',
                  compact: true,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final s = list[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      leading: ProductImage(
                        relativePath: s.product.imagePath,
                        name: s.product.name,
                        size: 50,
                        radius: 12,
                      ),
                      title: Text(
                        s.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${s.product.color.isNotEmpty ? 'رنگ ${s.product.color} • ' : ''}'
                        'موجودی ${faNumber(s.totalStock)} عدد',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      trailing: Icon(
                        Icons.chevron_left_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                      onTap: () => Navigator.pop(context, s),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
