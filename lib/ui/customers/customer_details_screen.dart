import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../state/app_state.dart';
import '../invoices/create_invoice_screen.dart';
import '../invoices/invoice_details_screen.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/invoice_status_chip.dart';
import '../widgets/money_text.dart';
import '../widgets/section_title.dart';
import '../widgets/stat_card.dart';
import 'customer_form_sheet.dart';

/// Customer profile: identity, live purchase summary and full invoice
/// history (newest first). Every invoice opens the standard invoice
/// details screen with its historical snapshots intact.
class CustomerDetailsScreen extends StatefulWidget {
  final int customerId;

  const CustomerDetailsScreen({super.key, required this.customerId});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  late Future<(CustomerSummary?, List<Invoice>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(CustomerSummary?, List<Invoice>)> _load() async {
    final s = Services.instance;
    final summary = await s.customers.getSummary(widget.customerId);
    final invoices = await s.invoices.listByCustomer(widget.customerId);
    return (summary, invoices);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<void> _createInvoice(Customer customer) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(initialCustomer: customer),
      ),
    );
    _refresh();
  }

  Future<void> _openInvoice(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailsScreen(invoiceId: id)),
    );
    _refresh();
  }

  Future<void> _edit(Customer customer) async {
    final saved = await CustomerFormSheet.show(context, existing: customer);
    if (saved) _refresh();
  }

  /// Destructive deletion is allowed only when no invoice references the
  /// customer — history must never break.
  Future<void> _delete(Customer customer) async {
    try {
      final n = await Services.instance.customers.invoiceCountOf(customer.id!);
      if (!mounted) return;
      if (n > 0) {
        await infoDialog(
          context,
          title: 'حذف مشتری ممکن نیست',
          icon: Icons.lock_outline_rounded,
          body: 'این مشتری ${faNumber(n)} فاکتور ثبت‌شده دارد.\n\n'
              'حذف مشتری، اعتبار و دسترسی به سابقه فاکتورهای او را از بین '
              'می‌برد؛ بنابراین حذف برای مشتری‌های دارای فاکتور انجام نمی‌شود. '
              'در صورت نیاز می‌توانید اطلاعات پروفایل را ویرایش کنید.',
        );
        return;
      }
      final ok = await confirmDialog(
        context,
        title: 'حذف مشتری',
        body: 'مشتری «${customer.name}» حذف می‌شود.\n\nاین عملیات قابل بازگشت نیست.',
        destructive: true,
        confirmLabel: 'حذف',
        icon: Icons.delete_outline_rounded,
      );
      if (!ok) return;
      await Services.instance.customers.delete(customer.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مشتری حذف شد')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        errorDialog(context, body: friendlyDbError(e));
      }
    }
  }

  String _initial(String name) {
    final n = name.trim();
    return n.isEmpty ? '؟' : n[0];
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('پروفایل مشتری')),
      body: FutureBuilder<(CustomerSummary?, List<Invoice>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'خطا در بارگذاری اطلاعات',
              subtitle: friendlyDbError(snap.error),
              buttonLabel: 'تلاش دوباره',
              onButton: _refresh,
            );
          }
          final summary = snap.data?.$1;
          final invoices = snap.data?.$2 ?? const <Invoice>[];
          if (summary == null) {
            return EmptyState(
              icon: Icons.person_off_outlined,
              title: 'مشتری یافت نشد',
              buttonLabel: 'بازگشت',
              onButton: () => Navigator.pop(context),
            );
          }
          final c = summary.customer;

          return RefreshIndicator(
            onRefresh: () async {
              final f = _load();
              setState(() => _future = f);
              await f;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                // ---- identity card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: scheme.primaryContainer,
                              foregroundColor: scheme.onPrimaryContainer,
                              child: Text(
                                _initial(c.name),
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800),
                                  ),
                                  if (c.hasPhone) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.phone_rounded,
                                            size: 15,
                                            color: scheme.onSurfaceVariant),
                                        const SizedBox(width: 6),
                                        Text(
                                          toPersianDigits(c.phone.trim()),
                                          style: TextStyle(
                                              fontSize: 13.5,
                                              color: scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'ویرایش مشتری',
                              icon: const Icon(Icons.edit_outlined),
                              color: scheme.onSurfaceVariant,
                              onPressed: () => _edit(c),
                            ),
                            IconButton(
                              tooltip: 'حذف مشتری',
                              icon: const Icon(Icons.delete_outline_rounded),
                              color: scheme.error,
                              onPressed: () => _delete(c),
                            ),
                          ],
                        ),
                        if (c.hasNotes) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.notes_rounded,
                                    size: 16, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    c.notes.trim(),
                                    style: TextStyle(
                                        fontSize: 13,
                                        height: 1.8,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ---- live purchase summary (computed from invoices)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تعداد فاکتور',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                faNumber(summary.invoiceCount),
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 38,
                          color: scheme.outlineVariant,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مجموع خرید',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              MoneyText(
                                summary.totalSpent,
                                ctrl.currencyLabel,
                                fontSize: 16.5,
                                color: scheme.primary,
                                weight: FontWeight.w800,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ---- fast path back into the sales flow
                FilledButton.icon(
                  onPressed: () => _createInvoice(c),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('ثبت فاکتور برای این مشتری'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
                const SizedBox(height: 26),

                // ---- full invoice history (newest first)
                SectionTitle('سابقه فاکتورها'),
                const SizedBox(height: 12),
                if (invoices.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'هنوز فاکتوری برای این مشتری ثبت نشده است',
                    subtitle: 'با دکمه بالا می‌توانید اولین فاکتور او را ثبت کنید.',
                    compact: true,
                  )
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < invoices.length; i++) ...[
                          if (i > 0)
                            const Divider(
                                height: 1, indent: 14, endIndent: 14),
                          ListTile(
                            leading: InvoiceNumberAvatar(
                                number: invoices[i].number),
                            title: Text(
                              '${faDateShort(invoices[i].createdAt)} • '
                              '${faNumber(invoices[i].itemCount)} قلم',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                faTime(invoices[i].createdAt),
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                MoneyText(
                                  invoices[i].total,
                                  ctrl.currencyLabel,
                                  fontSize: 13.5,
                                ),
                                const SizedBox(height: 4),
                                InvoiceStatusChip(
    status: invoices[i].status,
                                  fontSize: 10.5,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                ),
                              ],
                            ),
                            onTap: () => _openInvoice(invoices[i].id!),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
