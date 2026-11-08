import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

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
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
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
