import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../customers/customer_field.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/money_text.dart';
import 'invoice_details_screen.dart';
import 'pick_product_sheet.dart';
import 'pick_variant_sheet.dart';

/// Fast invoice composition screen: customer + items + payment status +
/// optional description + total + save. Draft items persist while
/// product/variant pickers open on top.
///
/// The customer is selected/created inline at the top of the form
/// (search suggestions + one-tap inline creation) — never in a separate
/// customer-management step.
class CreateInvoiceScreen extends StatefulWidget {
  final Customer? initialCustomer;

  const CreateInvoiceScreen({super.key, this.initialCustomer});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _customerKey = GlobalKey<CustomerFieldState>();
  Customer? _customer;
  final List<InvoiceDraftItem> _items = [];

  /// Payment status — every new invoice starts as «پرداخت نشده» (Unpaid)
  /// and the user may switch it before saving.
  InvoiceStatus _status = InvoiceStatus.unpaid;

  /// Optional free-text description of the invoice.
  final _descCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _customer = widget.initialCustomer; // pre-selected from customer profile
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  int get _total => _items.fold(0, (s, i) => s + i.lineTotal);

  Future<void> _addProduct() async {
    final picked = await showModalBottomSheet<ProductSummary>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ProductPickerSheet(),
    );
    if (picked == null || !mounted) return;

    final item = await showModalBottomSheet<InvoiceDraftItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VariantPickerSheet(product: picked.product),
    );
    if (item == null || !mounted) return;

    setState(() {
      final idx = _items.indexWhere((e) => e.variantId == item.variantId);
      if (idx >= 0) {
        final existing = _items[idx];
        final merged = existing.quantity + item.quantity;
        _items[idx] =
            existing.copyWith(quantity: merged.clamp(1, existing.availableStock));
        if (merged > existing.availableStock) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعداد به حداکثر موجودی انبار محدود شد'),
            ),
          );
        }
      } else {
        _items.add(item);
      }
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    // Resolve the customer: the selected one, or the typed name (an exact
    // match is reused; otherwise the customer is created right away).
    final customer = await _customerKey.currentState?.resolveOrCreate();
    if (!mounted) return;
    if (customer == null) {
      await errorDialog(context, body: 'نام مشتری را وارد کنید.');
      return;
    }
    if (_items.isEmpty) {
      await errorDialog(context, body: 'حداقل یک قلم کالا به فاکتور اضافه کنید.');
      return;
    }
    setState(() => _saving = true);
    try {
      final invoice = await Services.instance.invoices.createInvoice(
        customerName: customer.name,
        customerId: customer.id,
        items: _items,
        status: _status,
        description: _descCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فاکتور ذخیره شد و موجودی انبار به‌روزرسانی شد ✓'),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceDetailsScreen(invoiceId: invoice.id!),
          ),
        );
      }
    } on InsufficientStockException catch (e) {
      await _syncStocks();
      if (mounted) {
        errorDialog(
          context,
          title: 'موجودی کافی نیست',
          body:
              '«${e.productName}» (سایز ${e.variantName})\n\n'
              'موجودی فعلی انبار: ${faNumber(e.available)} عدد\n\n'
              'اقلام فاکتور با موجودی جدید اصلاح شدند؛ لطفاً دوباره تلاش کنید.',
        );
      }
    } catch (e) {
      if (mounted) {
        errorDialog(
          context,
          title: 'ذخیره فاکتور ممکن نشد',
          body: 'مشکلی پیش آمد. لطفاً دوباره تلاش کنید.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Re-reads live stock for every draft item and clamps quantities —
  /// used after an insufficient-stock rejection.
  Future<void> _syncStocks() async {
    final s = Services.instance;
    final updated = <InvoiceDraftItem>[];
    for (final it in _items) {
      final full = await s.products.getFull(it.productId);
      if (full == null) continue;
      ProductVariant? vv;
      for (final v in full.$2) {
        if (v.id == it.variantId) vv = v;
      }
      if (vv == null || vv.stock <= 0) continue;
      final qty = it.quantity > vv.stock ? vv.stock : it.quantity;
      updated.add(InvoiceDraftItem(
        variantId: it.variantId,
        productId: it.productId,
        productName: it.productName,
        productColor: it.productColor,
        variantName: it.variantName,
        quantity: qty,
        unitPrice: it.unitPrice,
        availableStock: vv.stock,
      ));
    }
    if (mounted) {
      setState(() {
        _items
          ..clear()
          ..addAll(updated);
      });
    }
  }

  /// Card for one draft item row inside the composition list.
  Widget _draftItemCard(
    InvoiceDraftItem it,
    AppSettingsController ctrl,
    ColorScheme scheme,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsets.only(left: 8, right: 14, top: 4, bottom: 4),
        title: Text(
          it.productName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'سایز ${it.variantName} • ${faNumber(it.quantity)} × ${ctrl.money(it.unitPrice)}',
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyText(
              it.lineTotal,
              ctrl.currencyLabel,
              fontSize: 14,
            ),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              tooltip: 'حذف ردیف',
              onPressed: () => setState(() => _items.remove(it)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('ثبت فاکتور جدید')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: CustomerField(
              key: _customerKey,
              selected: _customer,
              onChanged: (c) => setState(() => _customer = c),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              children: [
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: EmptyState(
                      icon: Icons.shopping_bag_outlined,
                      title: 'کالایی انتخاب نشده است',
                      subtitle:
                          'با دکمه «افزودن کالا» محصولات را به فاکتور اضافه کنید.',
                      compact: true,
                    ),
                  )
                else ...[
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _draftItemCard(_items[i], ctrl, scheme),
                  ],
                ],
                const SizedBox(height: 14),

                // ---- payment status (Paid / Unpaid) — must be chosen
                // before saving; defaults to Unpaid.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'وضعیت پرداخت',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<InvoiceStatus>(
                          segments: const [
                            ButtonSegment(
                              value: InvoiceStatus.unpaid,
                              icon: Icon(Icons.schedule_rounded, size: 18),
                              label: Text('پرداخت نشده'),
                            ),
                            ButtonSegment(
                              value: InvoiceStatus.paid,
                              icon: Icon(Icons.check_circle_rounded,
                                  size: 18),
                              label: Text('پرداخت شده'),
                            ),
                          ],
                          selected: {_status},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) =>
                              setState(() => _status = s.first),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- optional free-text description (hidden cost: none
                // while empty — a single-line field that grows as typed).
                TextField(
                  controller: _descCtrl,
                  minLines: 1,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات فاکتور (اختیاری)',
                    hintText: 'مثلاً شرایط تحویل، یادداشت تخفیف…',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                    label: const Text('افزودن کالا'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Text(
                            'جمع کل',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: MoneyText(
                              _total,
                              ctrl.currencyLabel,
                              key: ValueKey(_total),
                              fontSize: 17,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: (_saving || _items.isEmpty) ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text('ذخیره فاکتور'),
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
