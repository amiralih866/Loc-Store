import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../models/customer.dart';
import '../../state/app_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import 'customer_details_screen.dart';
import 'customer_form_sheet.dart';

/// Customers section — an automatic, read-mostly directory built from
/// invoice activity. Customers are normally created inline during invoice
/// creation; this screen is for browsing history and managing profiles.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _query = '';
  late Future<List<CustomerSummary>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    setState(
        () => _future = Services.instance.customers.listSummaries(query: _query));
  }

  Future<void> _openDetails(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customerId: id)),
    );
    _refresh();
  }

  Future<void> _addCustomer() async {
    final saved = await CustomerFormSheet.show(context);
    if (saved) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('مشتری‌ها')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomer,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('مشتری جدید'),
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
                hintText: 'جستجوی مشتری…',
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CustomerSummary>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'خطا در بارگذاری مشتری‌ها',
                    subtitle: friendlyDbError(snap.error),
                    buttonLabel: 'تلاش دوباره',
                    onButton: _refresh,
                  );
                }
                final customers = snap.data ?? const <CustomerSummary>[];
                if (customers.isEmpty) {
                  if (_query.isNotEmpty) {
                    return const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'نتیجه‌ای یافت نشد',
                      subtitle: 'نام دیگری را جستجو کنید.',
                    );
                  }
                  // Meaningful empty state — first customers appear
                  // automatically from the invoice flow, no manual step.
                  return const EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'هنوز مشتری‌ای ندارید',
                    subtitle:
                        'مشتری‌ها هنگام ثبت فاکتور به‌صورت خودکار ساخته می‌شوند '
                        'و اینجا نمایش داده می‌شوند.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    final f = Services.instance.customers
                        .listSummaries(query: _query);
                    setState(() => _future = f);
                    await f;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                    children: [
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < customers.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                    height: 1, indent: 14, endIndent: 14),
                              ListTile(
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: scheme.primaryContainer,
                                  foregroundColor: scheme.onPrimaryContainer,
                                  child: Text(
                                    _initial(customers[i].customer.name),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                                title: Text(
                                  customers[i].customer.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    '${faNumber(customers[i].invoiceCount)} فاکتور'
                                    ' • ${ctrl.money(customers[i].totalSpent)}',
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                onTap: () =>
                                    _openDetails(customers[i].customer.id!),
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
          ),
        ],
      ),
    );
  }

  String _initial(String name) {
    final n = name.trim();
    return n.isEmpty ? '؟' : n[0];
  }
}
