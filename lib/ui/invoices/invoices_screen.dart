import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../core/services.dart';
import '../../models/invoice.dart';
import '../../state/app_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/invoice_status_chip.dart';
import '../widgets/money_text.dart';
import '../widgets/stat_card.dart';
import 'create_invoice_screen.dart';
import 'invoice_details_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  String _query = '';
  late Future<List<Invoice>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = Services.instance.invoices.listInvoices(query: _query));
  }

  Future<void> _openCreate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateInvoiceScreen()),
    );
    _refresh();
  }

  Future<void> _openDetails(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailsScreen(invoiceId: id)),
    );
    _refresh();
  }

  String _dayLabel(DateTime dt) {
    final j = jalaliFromDateTime(dt);
    final now = DateTime.now();
    if (j == jalaliFromDateTime(now)) return 'امروز';
    if (j == jalaliFromDateTime(now.subtract(const Duration(days: 1)))) {
      return 'دیروز';
    }
    return '${weekdaysFa[dt.weekday - 1]} ${toPersianDigits('${j.day}')} ${jalaliMonths[j.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();

    return Scaffold(
      appBar: AppBar(title: const Text('فاکتورها')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text('ثبت فاکتور'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              onChanged: (v) {
                _query = v;
                _refresh();
              },
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'جستجوی شماره فاکتور یا نام مشتری…',
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Invoice>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'خطا در بارگذاری فاکتورها',
                    subtitle: friendlyDbError(snap.error),
                    buttonLabel: 'تلاش دوباره',
                    onButton: _refresh,
                  );
                }
                final invoices = snap.data ?? const <Invoice>[];
                if (invoices.isEmpty) {
                  if (_query.isNotEmpty) {
                    return const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'نتیجه‌ای یافت نشد',
                      subtitle: 'شماره فاکتور یا نام مشتری دیگری را جستجو کنید.',
                    );
                  }
                  return EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'هنوز فاکتوری صادر نشده است',
                    subtitle: 'اولین فاکتور خود را ثبت کنید تا اینجا نمایش داده شود.',
                    buttonLabel: 'ثبت فاکتور',
                    onButton: _openCreate,
                  );
                }

                // Group by Jalali day (newest first — list is already sorted).
                final groups = <String, List<Invoice>>{};
                for (final inv in invoices) {
                  groups.putIfAbsent(_dayLabel(inv.createdAt), () => []).add(inv);
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    final f = Services.instance.invoices
                        .listInvoices(query: _query);
                    setState(() => _future = f);
                    await f;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 14, bottom: 10),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < entry.value.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                      height: 1, indent: 14, endIndent: 14),
                                ListTile(
                                  leading: InvoiceNumberAvatar(
                                      number: entry.value[i].number),
                                  title: Text(
                                    entry.value[i].customerName.isEmpty
                                        ? 'مشتری ناشناس'
                                        : entry.value[i].customerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${faNumber(entry.value[i].itemCount)} قلم • ${faTime(entry.value[i].createdAt)}',
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                  trailing: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      MoneyText(
                                        entry.value[i].total,
                                        ctrl.currencyLabel,
                                        fontSize: 13.5,
                                      ),
                                      const SizedBox(height: 4),
                                      InvoiceStatusChip(
    status: entry.value[i].status,
                                        fontSize: 10.5,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _openDetails(entry.value[i].id!),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
