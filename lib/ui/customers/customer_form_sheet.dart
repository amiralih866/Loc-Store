import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../models/customer.dart';
import '../widgets/dialogs.dart';

/// Bottom-sheet form for creating or editing a customer (name / phone /
/// notes). Used by the Customers screen (manual add, edit) — the invoice
/// flow itself creates customers inline via [CustomerField].
class CustomerFormSheet extends StatefulWidget {
  final Customer? existing; // null → create mode

  const CustomerFormSheet({super.key, this.existing});

  /// Returns true when the customer was saved.
  static Future<bool> show(BuildContext context, {Customer? existing}) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CustomerFormSheet(existing: existing),
    );
    return res ?? false;
  }

  @override
  State<CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends State<CustomerFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      await errorDialog(context, body: 'نام مشتری را وارد کنید.');
      return;
    }
    setState(() => _saving = true);
    try {
      final s = Services.instance;
      if (widget.existing == null) {
        await s.customers.create(
          name: name,
          phone: _phone.text,
          notes: _notes.text,
        );
      } else {
        await s.customers.update(Customer(
          id: widget.existing!.id,
          name: name,
          phone: _phone.text,
          notes: _notes.text,
          createdAt: widget.existing!.createdAt,
        ));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        await errorDialog(context, body: friendlyDbError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isEdit ? Icons.edit_rounded : Icons.person_add_alt_rounded,
                  size: 21,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  isEdit ? 'ویرایش مشتری' : 'مشتری جدید',
                  style: const TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !isEdit,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'نام و نام خانوادگی *',
                hintText: 'مثلاً علی رضایی',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'شماره تماس (اختیاری)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'یادداشت (اختیاری)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (isEdit) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ویرایش اطلاعات، فاکتورهای قبلی را تغییر نمی‌دهد.',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
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
