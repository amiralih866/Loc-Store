import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../models/invoice.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../invoices/invoice_details_screen.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/money_text.dart';
import '../widgets/product_image.dart';
import '../widgets/qty_stepper.dart';
import '../widgets/section_title.dart';
import '../widgets/stat_card.dart';
import '../widgets/stock_badge.dart';
import 'product_edit_screen.dart';

class _Details {
  final Product product;
  final List<ProductVariant> variants;
  final int usageCount;

  /// Sales history grouped by variant/type, computed live from
  /// invoice-item data (most sold first).
  final List<VariantSalesGroup> history;

  const _Details(this.product, this.variants, this.usageCount, this.history);
}

class ProductDetailsScreen extends StatefulWidget {
  final int productId;

  const ProductDetailsScreen({super.key, required this.productId});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  late Future<_Details?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Details?> _load() async {
    final s = Services.instance;
    final full = await s.products.getFull(widget.productId);
    if (full == null) return null;
    final usage = await s.products.usageCount(widget.productId);
    final history = await s.invoices.productSalesHistory(widget.productId);
    return _Details(full.$1, full.$2, usage, history);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<void> _edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductEditScreen(productId: widget.productId),
      ),
    );
    _refresh();
  }

  Future<void> _archiveOrDelete(_Details d) async {
    final products = Services.instance.products;
    try {
      if (d.usageCount == 0) {
        final ok = await confirmDialog(
          context,
          title: 'حذف کالا',
          body: '«${d.product.name}» و همه سایزهای آن برای همیشه حذف می‌شوند. این عملیات قابل بازگشت نیست.',
          destructive: true,
          confirmLabel: 'حذف',
          icon: Icons.delete_outline_rounded,
        );
        if (!ok) return;
        await products.deleteHard(widget.productId);
        if (mounted) Navigator.pop(context, true);
      } else if (d.product.active) {
        final ok = await confirmDialog(
          context,
          title: 'بایگانی کالا',
          body:
              'این کالا در ${faNumber(d.usageCount)} قلم از فاکتورهای قبلی استفاده شده است.\n\n'
              'برای حفظ دقت فاکتورهای قبلی، کالا به‌جای حذف، بایگانی می‌شود: از لیست انبار پنهان می‌شود اما تاریخچه فاکتورها سالم می‌ماند.',
          confirmLabel: 'بایگانی',
          icon: Icons.archive_outlined,
        );
        if (!ok) return;
        await products.setArchived(widget.productId, true);
        if (mounted) Navigator.pop(context, true);
      } else {
        await products.setArchived(widget.productId, false);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) errorDialog(context, body: friendlyDbError(e));
    }
  }

  Future<void> _variantSheet(Product product, ProductVariant v, int threshold) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VariantSheet(product: product, variant: v),
    );
    if (changed == true) _refresh();
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
      appBar: AppBar(title: const Text('جزئیات کالا'), actions: [
        IconButton(
          icon: const Icon(Icons.edit_rounded),
          tooltip: 'ویرایش',
          onPressed: _edit,
        ),
      ]),
      body: FutureBuilder<_Details?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data;
          if (d == null) {
            return EmptyState(
              icon: Icons.search_off_rounded,
              title: 'کالا یافت نشد',
              buttonLabel: 'بازگشت',
              onButton: () => Navigator.pop(context),
            );
          }
          final p = d.product;
          final totalStock = d.variants.fold<int>(0, (s, v) => s + v.stock);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      ProductImage(
                        relativePath: p.imagePath,
                        name: p.name,
                        size: 176,
                        radius: 24,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        p.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.5,
                        ),
                      ),
                      if (p.color.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'رنگ: ${p.color}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      MoneyText(
                        p.defaultPrice,
                        ctrl.currencyLabel,
                        fontSize: 15,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _miniStat(
                      context,
                      'سایزها',
                      faNumber(d.variants.length),
                      Icons.category_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _miniStat(
                      context,
                      'موجودی کل',
                      '${faNumber(totalStock)} عدد',
                      Icons.inventory_2_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              SectionTitle('سایزها و موجودی'),
              const SizedBox(height: 10),
              if (d.variants.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'هیچ سایزی تعریف نشده است. با ویرایش کالا سایز اضافه کنید.',
                      style: TextStyle(fontSize: 13.5, height: 1.7),
                    ),
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < d.variants.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 14, endIndent: 14),
                        ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              d.variants[i].name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          title: d.variants[i].customPrice == null
                              ? const Text('قیمت پیش‌فرض',
                                  style: TextStyle(fontSize: 13))
                              : MoneyText(
                                  d.variants[i].customPrice!,
                                  ctrl.currencyLabel,
                                  fontSize: 13.5,
                                ),
                          subtitle: d.variants[i].customPrice == null
                              ? null
                              : Text(
                                  'قیمت اختصاصی',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                          trailing: StockBadge(
                            stock: d.variants[i].stock,
                            lowThreshold: ctrl.lowStockThreshold,
                          ),
                          onTap: () =>
                              _variantSheet(p, d.variants[i], ctrl.lowStockThreshold),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 26),

              // ---- Invoice History / Purchase History, organized by
              // variant/type. Totals are computed live from invoice-item
              // rows; nothing here is stored on the product itself.
              SectionTitle('تاریخچه فروش'),
              const SizedBox(height: 10),
              if (d.history.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'هنوز فاکتوری برای این کالا ثبت نشده است. با ثبت اولین فاکتور، سابقه فروش هر سایز اینجا نمایش داده می‌شود.',
                      style: TextStyle(fontSize: 13.5, height: 1.7),
                    ),
                  ),
                )
              else
                for (var gi = 0; gi < d.history.length; gi++) ...[
                  if (gi > 0) const SizedBox(height: 12),
                  _salesGroupCard(d.history[gi]),
                ],
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _edit,
                      icon: const Icon(Icons.edit_rounded, size: 19),
                      label: const Text('ویرایش کالا'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _archiveOrDelete(d),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            d.usageCount == 0 && p.active ? scheme.error : null,
                        side: BorderSide(
                          color: d.usageCount == 0 && p.active
                              ? scheme.error.withValues(alpha: 0.5)
                              : scheme.outline.withValues(alpha: 0.6),
                        ),
                      ),
                      icon: Icon(
                        d.usageCount == 0
                            ? Icons.delete_outline_rounded
                            : (p.active
                                ? Icons.archive_outlined
                                : Icons.unarchive_rounded),
                        size: 19,
                      ),
                      label: Text(
                        d.usageCount == 0
                            ? 'حذف کالا'
                            : (p.active ? 'بایگانی کالا' : 'بازگردانی کالا'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// One variant section of the sales history: header (variant + total
  /// sold, e.g. «XL — ۱۲ عدد فروش») and one row per invoice that sold it.
  Widget _salesGroupCard(VariantSalesGroup g) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'سایز ${g.variantName}',
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${faNumber(g.totalSold)} عدد فروش',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14),
          for (var i = 0; i < g.entries.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 14, endIndent: 14),
            ListTile(
              leading: InvoiceNumberAvatar(
                  number: g.entries[i].invoiceNumber, size: 42),
              title: Text(
                g.entries[i].customerName.isEmpty
                    ? 'مشتری ناشناس'
                    : g.entries[i].customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'فاکتور #${faNumber(g.entries[i].invoiceNumber)} • ${faDateShort(g.entries[i].createdAt)}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              trailing: Text(
                '${faNumber(g.entries[i].quantity)} عدد',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              onTap: () => _openInvoice(g.entries[i].invoiceId),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for adjusting a variant: stock (restock / decrease),
/// optional custom price, and a separate destructive delete button.
class _VariantSheet extends StatefulWidget {
  final Product product;
  final ProductVariant variant;

  const _VariantSheet({required this.product, required this.variant});

  @override
  State<_VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends State<_VariantSheet> {
  late int _newStock;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _newStock = widget.variant.stock;
    _priceCtrl = TextEditingController(
      text: widget.variant.customPrice == null ? '' : '${widget.variant.customPrice}',
    );
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final products = Services.instance.products;
    final priceText = _priceCtrl.text.trim();
    final price = tryParseUserInt(priceText);
    if (priceText.isNotEmpty && (price == null || price < 0)) {
      await errorDialog(context, body: 'قیمت وارد شده معتبر نیست.');
      return;
    }
    try {
      await products.setVariantStock(
          variantId: widget.variant.id!, stock: _newStock);
      await products.updateVariant(
        variantId: widget.variant.id!,
        customPrice: priceText.isEmpty ? null : price,
        clearPrice: priceText.isEmpty,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) errorDialog(context, body: friendlyDbError(e));
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'حذف سایز',
      body:
          'سایز «${widget.variant.name}» بدون بازگشت موجودی به انبار حذف می‌شود.\n\n'
          'فاکتورهای قبلی که این سایز را دارند بدون تغییر باقی می‌مانند.',
      destructive: true,
      confirmLabel: 'حذف',
      icon: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    try {
      await Services.instance.products.deleteVariant(widget.variant.id!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) errorDialog(context, body: friendlyDbError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final v = widget.variant;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سایز ${v.name}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      widget.product.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StockBadge(stock: v.stock, lowThreshold: ctrl.lowStockThreshold),
            ],
          ),
          const SizedBox(height: 20),
          Text('اصلاح موجودی (بازگشت یا کسر)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              QtyStepper(
                value: _newStock,
                min: 0,
                max: 99999,
                onChanged: (n) => setState(() => _newStock = n),
              ),
              const Spacer(),
              Text(
                'موجودی فعلی: ${faNumber(v.stock)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'قیمت اختصاصی — خالی = قیمت پیش‌فرض کالا',
              suffixText: ctrl.currencyLabel,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('ذخیره تغییرات'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            label: const Text('حذف این سایز'),
          ),
        ],
      ),
    );
  }
}
