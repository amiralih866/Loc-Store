import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../models/invoice.dart' show InvoiceDraftItem;
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../widgets/money_text.dart';
import '../widgets/qty_stepper.dart';
import '../widgets/stock_badge.dart';

/// Second step: pick a size (variant), quantity shows live resolved price
/// and available stock. Returns an [InvoiceDraftItem] via Navigator.pop.
class VariantPickerSheet extends StatefulWidget {
  final Product product;

  const VariantPickerSheet({super.key, required this.product});

  @override
  State<VariantPickerSheet> createState() => _VariantPickerSheetState();
}

class _VariantPickerSheetState extends State<VariantPickerSheet> {
  List<ProductVariant> _variants = [];
  bool _loading = true;
  int? _selectedId;
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vs = await Services.instance.products.variantsOf(widget.product.id!);
    if (!mounted) return;
    setState(() {
      _variants = vs;
      _loading = false;
      // Pre-select the first in-stock variant for a faster flow.
      for (final v in vs) {
        if (v.stock > 0) {
          _selectedId = v.id;
          break;
        }
      }
    });
  }

  ProductVariant? get _selected {
    for (final v in _variants) {
      if (v.id == _selectedId) return v;
    }
    return null;
  }

  int get _unitPrice {
    final s = _selected;
    if (s == null) return 0;
    return resolveUnitPrice(
      productDefault: widget.product.defaultPrice,
      variantCustom: s.customPrice,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
                      widget.product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    if (widget.product.color.isNotEmpty)
                      Text(
                        'رنگ ${widget.product.color}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'انتخاب سایز',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in _variants)
                  ChoiceChip(
                    label: Text(
                      v.stock == 0
                          ? '${v.name} (ناموجود)'
                          : '${v.name} — ${faNumber(v.stock)}',
                    ),
                    selected: _selectedId == v.id,
                    onSelected: v.stock > 0
                        ? (_) => setState(() {
                              _selectedId = v.id;
                              _qty = 1;
                            })
                        : null,
                    selectedColor: scheme.primaryContainer,
                    labelStyle: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: v.stock == 0
                          ? scheme.outline
                          : (_selectedId == v.id
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface),
                    ),
                  ),
              ],
            ),
          if (_selected != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'موجودی: ${faNumber(_selected!.stock)} عدد',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        StockBadge(
                          stock: _selected!.stock,
                          lowThreshold: ctrl.lowStockThreshold,
                          showQtyWhenLow: false,
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Text(
                          'تعداد',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        QtyStepper(
                          value: _qty,
                          min: 1,
                          max: _selected!.stock,
                          onChanged: (n) => setState(() => _qty = n),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Text(
                          'قیمت واحد',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                        const Spacer(),
                        MoneyText(
                          _unitPrice,
                          ctrl.currencyLabel,
                          fontSize: 13.5,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text(
                          'جمع این ردیف',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        MoneyText(
                          _unitPrice * _qty,
                          ctrl.currencyLabel,
                          fontSize: 15,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final s = _selected!;
                Navigator.pop(
                  context,
                  InvoiceDraftItem(
                    variantId: s.id!,
                    productId: widget.product.id!,
                    productName: widget.product.name,
                    productColor: widget.product.color,
                    variantName: s.name,
                    quantity: _qty,
                    unitPrice: _unitPrice,
                    availableStock: s.stock,
                  ),
                );
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('افزودن به فاکتور'),
            ),
          ],
        ],
      ),
    );
  }
}
