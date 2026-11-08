import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/image_store.dart';
import '../../models/invoice.dart';
import '../../services/invoice_image.dart';
import '../../services/share_service.dart';
import '../../state/app_state.dart';
import '../customers/customer_details_screen.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/invoice_status_chip.dart';
import '../widgets/money_text.dart';
import '../widgets/section_title.dart';

class InvoiceDetailsScreen extends StatefulWidget {
  final int invoiceId;

  const InvoiceDetailsScreen({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  Invoice? _inv;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inv =
          await Services.instance.invoices.getInvoice(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _inv = inv;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Quiet refresh after a meta edit (status/description) — no spinner.
  Future<void> _softReload() async {
    final inv =
        await Services.instance.invoices.getInvoice(widget.invoiceId);
    if (inv != null && mounted) setState(() => _inv = inv);
  }

  /// Persists the new payment status immediately from the details screen.
  Future<void> _updateStatus(InvoiceStatus status) async {
    if (_inv == null || _inv!.status == status) return;
    try {
      await Services.instance.invoices
          .updateInvoiceMeta(widget.invoiceId, status: status);
      if (!mounted) return;
      setState(() => _inv = null); // keep old text while reloading
      await _softReload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('وضعیت پرداخت: ${status.faLabel} ✓')),
        );
      }
    } catch (e) {
      if (mounted) errorDialog(context, body: friendlyDbError(e));
    }
  }

  /// Edits the optional invoice description in a bottom sheet. The sheet
  /// returns the new text (null = canceled); an empty string clears the
  /// description (and the section disappears from the screen).
  Future<void> _editDescription() async {
    final current = _inv?.description ?? '';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DescriptionSheet(initial: current),
    );
    if (result == null || !mounted) return; // canceled
    try {
      await Services.instance.invoices
          .updateInvoiceMeta(widget.invoiceId, description: result);
      await _softReload();
    } catch (e) {
      if (mounted) errorDialog(context, body: friendlyDbError(e));
    }
  }

  Future<void> _delete() async {
    final inv = _inv;
    if (inv == null || !mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'حذف فاکتور',
      body:
          'فاکتور شماره ${faNumber(inv.number)} حذف می‌شود و ${faNumber(inv.itemCount)} قلم کالای آن به انبار بازمی‌گردد.\n\nاین عملیات قابل بازگشت نیست.',
      destructive: true,
      confirmLabel: 'حذف',
      icon: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    try {
      await Services.instance.invoices.deleteInvoice(widget.invoiceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('فاکتور حذف شد و موجودی به انبار بازگشت ✓')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) errorDialog(context, body: friendlyDbError(e));
    }
  }

  Future<void> _shareImage() async {
    final inv = _inv;
    if (inv == null || !mounted) return;
    final ctrl = context.read<AppSettingsController>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('در حال ساخت تصویر فاکتور…'),
              ],
            ),
          ),
        ),
      ),
    );

    String? path;
    try {
      String? logoDir;
      if (ctrl.storeLogoPath != null) {
        logoDir = (await ImageStore.docs()).path;
      }
      path = await InvoiceImageGenerator().generate(
        invoice: inv,
        storeName: ctrl.storeName,
        storePhone: ctrl.storePhone,
        storeAddress: ctrl.storeAddress,
        currencyLabel: ctrl.currencyLabel,
        logoRelativePath: ctrl.storeLogoPath,
        logoDocsDirPath: logoDir,
        accent: ctrl.palette.seed,
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        errorDialog(context,
            body: 'ساخت تصویر فاکتور ممکن نشد. دوباره تلاش کنید.');
      }
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(path!),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('بستن'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await shareFile(path!,
                          text: 'فاکتور فروش شماره ${inv.number}');
                      if (!ok && ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('اشتراک‌گذاری ممکن نشد')),
                        );
                      }
                    },
                    icon: const Icon(Icons.share_rounded, size: 19),
                    label: const Text('اشتراک‌گذاری'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('جزئیات فاکتور')),
      body: _buildBody(ctrl, scheme),
    );
  }

  Widget _buildBody(AppSettingsController ctrl, ColorScheme scheme) {
    if (_loading && _inv == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'خطا در بارگذاری اطلاعات',
        subtitle: friendlyDbError(_error),
        buttonLabel: 'تلاش دوباره',
        onButton: _reload,
      );
    }
    final inv = _inv;
    if (inv == null) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'فاکتور یافت نشد',
        buttonLabel: 'بازگشت',
        onButton: () => Navigator.pop(context),
      );
    }

    final hasDescription = inv.description.trim().isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        // ---- header card: number, status chip, customer, date
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'فاکتور شماره ${faNumber(inv.number)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    InvoiceStatusChip(status: inv.status),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${faNumber(inv.itemCount)} قلم',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Historical name snapshot; tapping jumps to the
                // customer's live profile when the invoice is linked.
                InkWell(
                  onTap: inv.customerId == null
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerDetailsScreen(
                                  customerId: inv.customerId!),
                            ),
                          );
                          if (mounted) _softReload();
                        },
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 17,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          inv.customerName.isEmpty
                              ? 'مشتری ناشناس'
                              : inv.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (inv.customerId != null) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_left_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${faDateLong(inv.createdAt)} • ساعت ${faTime(inv.createdAt)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ---- payment status (editable in place) + optional description
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'وضعیت پرداخت',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    InvoiceStatusChip(status: inv.status),
                  ],
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
                      icon: Icon(Icons.check_circle_rounded, size: 18),
                      label: Text('پرداخت شده'),
                    ),
                  ],
                  selected: {inv.status},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _updateStatus(s.first),
                ),
                if (hasDescription) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'توضیحات',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'ویرایش توضیحات',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: scheme.onSurfaceVariant,
                        onPressed: _editDescription,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      inv.description.trim(),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.8,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _editDescription,
                    icon: const Icon(Icons.add_comment_outlined, size: 18),
                    label: const Text('افزودن توضیحات…'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SectionTitle('اقلام فاکتور'),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < inv.items.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 14, endIndent: 14),
                ListTile(
                  title: Text(
                    inv.items[i].productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${inv.items[i].productColor.isNotEmpty ? 'رنگ ${inv.items[i].productColor} • ' : ''}'
                      'سایز ${inv.items[i].variantName} • '
                      '${faNumber(inv.items[i].quantity)} × ${ctrl.money(inv.items[i].unitPrice)}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  trailing: MoneyText(
                    inv.items[i].total,
                    ctrl.currencyLabel,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                const Text(
                  'جمع کل',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                MoneyText(
                  inv.total,
                  ctrl.currencyLabel,
                  fontSize: 18,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: _shareImage,
          icon: const Icon(Icons.ios_share_rounded, size: 20),
          label: const Text('اشتراک‌گذاری به‌صورت تصویر'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _delete,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          label: const Text('حذف فاکتور'),
        ),
      ],
    );
  }
}

/// Bottom sheet for editing the invoice description — optional multiline
/// free text, no predefined format. Pops with the new text (empty string
/// clears it) or null when canceled.
class _DescriptionSheet extends StatefulWidget {
  final String initial;

  const _DescriptionSheet({required this.initial});

  @override
  State<_DescriptionSheet> createState() => _DescriptionSheetState();
}

class _DescriptionSheetState extends State<_DescriptionSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          Text(
            'توضیحات فاکتور',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'متن دلخواه — اختیاری. برای حذف توضیحات، خالی بگذارید و ذخیره کنید.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            minLines: 3,
            maxLines: 8,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'مثلاً شرایط تحویل، یادداشت تخفیف، شماره مرجع…',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            child: const Text('ذخیره توضیحات'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
        ],
      ),
    );
  }
}
