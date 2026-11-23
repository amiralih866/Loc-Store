import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../state/app_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/product_image.dart';

class StoreInfoScreen extends StatefulWidget {
  const StoreInfoScreen({super.key});

  @override
  State<StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends State<StoreInfoScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _card;
  late final TextEditingController _cardHolder;
  XFile? _pickedLogo;
  bool _logoRemoved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<AppSettingsController>();
    _name = TextEditingController(text: ctrl.storeName);
    _phone = TextEditingController(text: ctrl.storePhone);
    _address = TextEditingController(text: ctrl.storeAddress);
    // Prefill the card number in its grouped, readable form.
    _card = TextEditingController(text: formatCardNumber(ctrl.cardNumber));
    _cardHolder = TextEditingController(text: ctrl.cardHolderName);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _card.dispose();
    _cardHolder.dispose();
    super.dispose();
  }

  Future<void> _logoSheet() async {
    final ctrl = context.read<AppSettingsController>();
    final hasLogo = _pickedLogo != null ||
        (_logoRemoved == false && (ctrl.storeLogoPath?.isNotEmpty ?? false));
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
            if (hasLogo)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: Theme.of(ctx).colorScheme.error),
                title: Text('حذف لوگو',
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
        _pickedLogo = null;
        _logoRemoved = true;
      });
      return;
    }
    try {
      final x = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 88,
      );
      if (x != null) {
        setState(() {
          _pickedLogo = x;
          _logoRemoved = false;
        });
      }
    } catch (_) {
      if (mounted) {
        errorDialog(context, body: 'دسترسی به دوربین یا گالری ممکن نشد.');
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final ctrl = context.read<AppSettingsController>();

      // Generic sanity check on the optional card number — digits-only
      // length check, no bank/issuer-specific validation.
      final cardDigits = normalizeCardNumber(_card.text);
      if (cardDigits.isNotEmpty && cardDigits.length < 12) {
        if (mounted) {
          errorDialog(
            context,
            body: 'شماره کارت واردشده کامل نیست. دست‌کم ۱۲ رقم وارد کنید یا '
                'فیلد را خالی بگذارید.',
          );
        }
        return;
      }

      String? logoPath;
      if (_pickedLogo != null) {
        logoPath = await Services.instance.images.saveLogo(
          _pickedLogo!,
          replaceOld: ctrl.storeLogoPath,
        );
      }
      await ctrl.setStoreInfo(
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
        logoPath: logoPath ?? (_logoRemoved ? '' : null),
      );
      // Store-level payment info — optional, saved with the same button.
      await ctrl.setPaymentInfo(
        cardNumber: cardDigits,
        holderName: _cardHolder.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اطلاعات فروشگاه ذخیره شد ✓')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) errorDialog(context, body: friendlyDbError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;

    Widget logoPreview;
    if (_pickedLogo != null) {
      logoPreview = ClipOval(
        child: Image.file(
          File(_pickedLogo!.path),
          width: 96,
          height: 96,
          fit: BoxFit.cover,
        ),
      );
    } else {
      logoPreview = _logoRemoved || ctrl.storeLogoPath == null
          ? Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.storefront_rounded,
                  size: 40, color: scheme.primary),
            )
          : ProductImage(
              relativePath: ctrl.storeLogoPath,
              name: ctrl.storeName.isEmpty ? 'فروشگاه' : ctrl.storeName,
              size: 96,
              radius: 48,
            );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('اطلاعات فروشگاه')),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Center(
              child: GestureDetector(
                onTap: _logoSheet,
                child: logoPreview,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'لوگوی فروشگاه (در تصویر فاکتور نمایش داده می‌شود)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'نام فروشگاه',
                hintText: 'مثلاً بوتیک مینا',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'شماره تماس',
                hintText: '09xxxxxxxxx',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'آدرس',
                hintText: 'آدرس فروشگاه (اختیاری)',
              ),
            ),

            // ---- payment information: optional store-level bank card,
            // used only when generating UNPAID invoice images.
            const SizedBox(height: 28),
            Row(
              children: [
                Icon(Icons.credit_card_rounded,
                    size: 19, color: scheme.primary),
                const SizedBox(width: 7),
                const Text(
                  'اطلاعات پرداخت',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'اختیاری — فقط روی تصویر فاکتورهای پرداخت‌نشده نمایش داده می‌شود.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _card,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              inputFormatters: [_CardNumberInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'شماره کارت',
                hintText: '6037 9912 3456 7890',
                helperText: 'اختیاری — کارت فروشگاه برای واریز مشتری',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _cardHolder,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'نام صاحب کارت',
                hintText: 'مثلاً امیر احمدی',
                helperText: 'اختیاری',
              ),
            ),
            const SizedBox(height: 28),
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
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live card-number input formatting: digits only (Persian/Arabic digits
/// are normalized to ASCII), grouped in blocks of four with spaces while
/// typing, and the cursor stays in place by counting the digits before it.
class _CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = normalizeCardNumber(newValue.text);

    var digitsBeforeCursor = 0;
    final sel = newValue.selection.baseOffset;
    if (sel < 0) {
      digitsBeforeCursor = digits.length;
    } else {
      for (var i = 0; i < sel && i < newValue.text.length; i++) {
        if (newValue.text[i] != ' ') digitsBeforeCursor++;
      }
    }

    final formatted = formatCardNumber(digits);
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCursor) {
      if (formatted[offset] != ' ') seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
