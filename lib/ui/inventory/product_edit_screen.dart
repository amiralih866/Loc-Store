import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/validators.dart';
import '../../models/invoice.dart' show DuplicateVariantException;
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/product_image.dart';
import '../widgets/section_title.dart';

/// One editable variant row inside the product form.
class _VRow {
  final int? id;
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController stock;

  _VRow({this.id, String name = '', String price = '', String stock = ''})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price),
        stock = TextEditingController(text: stock);

  void dispose() {
    name.dispose();
    price.dispose();
    stock.dispose();
  }
}

class ProductEditScreen extends StatefulWidget {
  final int? productId;

  const ProductEditScreen({super.key, this.productId});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _color = TextEditingController();
  final _price = TextEditingController();

  Product? _existing;
  String? _imagePath;
  bool _imageRemoved = false;
  XFile? _pickedImage;

  final List<_VRow> _rows = [];
  final Set<int> _removedIds = {};
  bool _loading = false;
  bool _saving = false;

  static const List<String> _quickSizes = [
    'S', 'M', 'L', 'XL', 'XXL', 'XXXL', '38', '40', '42', '44', '46',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.productId != null) {
      _loadExisting();
    } else {
      _addRow();
      _addRow();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _color.dispose();
    _price.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final full =
          await Services.instance.products.getFull(widget.productId!);
      if (full != null) {
        final (p, vs) = full;
        _existing = p;
        _imagePath = p.imagePath;
        _imageRemoved = false;
        _name.text = p.name;
        _color.text = p.color;
        _price.text = p.defaultPrice == 0 ? '' : '${p.defaultPrice}';
        _rows.clear();
        for (final v in vs) {
          _rows.add(_VRow(
            id: v.id,
            name: v.name,
            price: v.customPrice == null ? '' : '${v.customPrice}',
            stock: '${v.stock}',
          ));
        }
      }
    } catch (e) {
      if (mounted) errorDialog(context, body: friendlyDbError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  void _addRow([String preset = '']) {
    setState(() => _rows.add(_VRow(name: preset)));
  }

  Future<void> _imageActionSheet() async {
    final hasOld = _pickedImage != null || (_imagePath?.isNotEmpty ?? false);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('دوربین'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('گالری'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasOld)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: Theme.of(ctx).colorScheme.error),
                title: Text('حذف تصویر',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'remove') {
      setState(() {
        _pickedImage = null;
        _imagePath = null;
        _imageRemoved = true;
      });
      return;
    }
    try {
      final x = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (x != null) {
        setState(() {
          _pickedImage = x;
          _imageRemoved = false;
        });
      }
    } catch (_) {
      if (mounted) {
        errorDialog(context,
            body: 'دسترسی به دوربین یا گالری ممکن نشد. دوباره تلاش کنید.');
      }
    }
  }

  void _addQuickSize(String size) {
    final exists = _rows.any((r) => r.name.text.trim().toLowerCase() == size.toLowerCase());
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('سایز «$size» قبلاً اضافه شده است')),
      );
      return;
    }
    _addRow(size);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final inputs = <VariantInput>[];
    final seen = <String>{};
    for (final r in _rows) {
      final n = r.name.text.trim();
      if (n.isEmpty) {
        await errorDialog(context, body: 'نام همه سایزها را وارد کنید.');
        return;
      }
      final key = n.toLowerCase();
      if (!seen.add(key)) {
        await errorDialog(context, body: 'سایز «$n» تکراری است. نام‌ها باید یکتا باشند.');
        return;
      }
      final priceText = r.price.text.trim();
      final price = tryParseUserInt(priceText);
      if (priceText.isNotEmpty && (price == null || price < 0)) {
        await errorDialog(context, body: 'قیمت سایز «$n» معتبر نیست.');
        return;
      }
      final stock = tryParseUserInt(r.stock.text);
      if (stock == null || stock < 0) {
        await errorDialog(context, body: 'موجودی سایز «$n» را به‌صورت عدد معتبر وارد کنید.');
        return;
      }
      inputs.add(VariantInput(
        id: r.id,
        name: n,
        customPrice: priceText.isEmpty ? null : price,
        stock: stock,
      ));
    }
    if (inputs.isEmpty) {
      await errorDialog(context, body: 'حداقل یک سایز برای کالا اضافه کنید.');
      return;
    }

    final price = tryParseUserInt(_price.text.trim());
    if (price == null || price < 0) {
      await errorDialog(context, body: 'قیمت پیش‌فرض را به‌صورت عدد معتبر وارد کنید.');
      return;
    }

    setState(() => _saving = true);
    try {
      String? imagePath = _imagePath;
      if (_pickedImage != null) {
        imagePath = await Services.instance.images.saveProductImage(
          _pickedImage!,
          replaceOld: _imageRemoved ? null : _imagePath,
        );
      } else if (_imageRemoved && _existing?.imagePath != null) {
        await Services.instance.images.delete(_existing!.imagePath!);
        imagePath = null;
      }

      if (_existing == null) {
        await Services.instance.products.createProduct(
          name: _name.text,
          color: _color.text,
          defaultPrice: price,
          imagePath: imagePath,
          variants: inputs,
        );
      } else {
        final updated = _existing!.copyWith(
          name: _name.text.trim(),
          color: _color.text.trim(),
          defaultPrice: price,
          imagePath: imagePath,
          clearImage: imagePath == null,
          updatedAt: DateTime.now(),
        );
        await Services.instance.products.updateProduct(
          existing: updated,
          variants: inputs,
          removedVariantIds: _removedIds,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_existing == null ? 'کالا ذخیره شد ✓' : 'تغییرات ذخیره شد ✓')),
        );
        Navigator.pop(context, true);
      }
    } on DuplicateVariantException catch (e) {
      if (mounted) errorDialog(context, body: 'سایز «${e.name}» تکراری است.');
    } catch (e) {
      if (mounted) {
        errorDialog(context, body: 'ذخیره کالا ممکن نشد. لطفاً اطلاعات وارد شده را بررسی کنید.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;

    Widget preview;
    if (_pickedImage != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.file(
          File(_pickedImage!.path),
          width: 132,
          height: 132,
          fit: BoxFit.cover,
        ),
      );
    } else {
      preview = ProductImage(
        relativePath: _imagePath,
        name: _name.text.trim().isEmpty ? 'کالا' : _name.text.trim(),
        size: 132,
        radius: 22,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'افزودن کالا' : 'ویرایش کالا'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _imageActionSheet,
                      child: preview,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'تصویر کالا (اختیاری)',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'نام کالا *',
                      hintText: 'مثلاً تیشرت ساده',
                    ),
                    validator: (v) => validateRequired(v, 'نام کالا را وارد کنید'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _color,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'رنگ',
                      hintText: 'مثلاً مشکی',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'قیمت پیش‌فرض *',
                      suffixText: ctrl.currencyLabel,
                    ),
                    validator: (v) => validateMoneyField(v),
                  ),
                  const SizedBox(height: 28),
                  SectionTitle('سایزها'),
                  const SizedBox(height: 4),
                  Text(
                    'برای هر سایز می‌توانید قیمت اختصاصی و موجودی جداگانه تعیین کنید.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.7,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _rows.length; i++) _variantCard(_rows[i]),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _addRow(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('افزودن سایز'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final s in _quickSizes)
                        ActionChip(
                          label: Text(s),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _addQuickSize(s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  FilledButton(
                    onPressed: _saving ? null : _save,
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
                        : const Text('ذخیره کالا'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _variantCard(_VRow r) {
    final ctrl = context.watch<AppSettingsController>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: r.name,
                    decoration: const InputDecoration(
                      labelText: 'نام سایز *',
                      hintText: 'مثلاً M یا 40',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  tooltip: 'حذف سایز',
                  onPressed: () async {
                    if (r.id != null) {
                      final ok = await confirmDialog(
                        context,
                        title: 'حذف سایز',
                        body: 'این سایز از کالا حذف می‌شود. فاکتورهای قبلی بدون تغییر باقی می‌مانند.',
                        destructive: true,
                        confirmLabel: 'حذف',
                        icon: Icons.delete_outline_rounded,
                      );
                      if (!ok) return;
                    }
                    setState(() {
                      _rows.remove(r);
                      if (r.id != null) _removedIds.add(r.id!);
                      r.dispose();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: r.price,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'قیمت اختصاصی (اختیاری)',
                      suffixText: ctrl.currencyLabel,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: r.stock,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _existing == null ? 'موجودی اولیه' : 'موجودی فعلی',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
