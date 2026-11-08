import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../models/customer.dart';
import '../../state/app_state.dart';

/// Inline customer selection for the invoice form.
///
/// The user simply starts typing: existing customers are suggested live
/// with their invoice count and total purchases. When the typed name is
/// not an exact existing match, an inline «افزودن» action creates the
/// customer immediately — without leaving the invoice form.
///
/// Customer creation happens *inside this field*; there is no separate
/// customer-creation step in the sales flow.
class CustomerField extends StatefulWidget {
  final Customer? selected;
  final ValueChanged<Customer?> onChanged;

  const CustomerField({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<CustomerField> createState() => CustomerFieldState();
}

class CustomerFieldState extends State<CustomerField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<CustomerSummary> _results = const [];
  bool _open = false;
  int _reqId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Save-time resolution: the selected customer, or the typed text
  /// (created / reused through the exact-name dedupe rule). Returns null
  /// when nothing was entered.
  Future<Customer?> resolveOrCreate() async {
    final sel = widget.selected;
    if (sel != null) return sel;
    final t = _controller.text.trim();
    if (t.isEmpty) return null;
    final (c, _) = await Services.instance.customers.createOrGetByName(t);
    return c;
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _results = const [];
        _open = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), _search);
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    final req = ++_reqId;
    final res = await Services.instance.customers.suggestions(q);
    if (!mounted || req != _reqId) return; // stale response — ignore
    setState(() {
      _results = res;
      _open = true;
    });
  }

  void _select(Customer c) {
    _debounce?.cancel();
    _controller.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _open = false;
      _results = const [];
    });
    widget.onChanged(c);
  }

  Future<void> _addNew(String name) async {
    final (c, _) = await Services.instance.customers.createOrGetByName(name);
    if (mounted) _select(c);
  }

  String _initial(String name) {
    final n = name.trim();
    return n.isEmpty ? '؟' : n[0];
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppSettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;

    // ---- selected state: chip with a remove action. The × only detaches
    // the customer from this invoice; it never deletes the customer.
    if (selected != null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'مشتری',
          prefixIcon: Icon(Icons.person_rounded, color: scheme.primary),
          suffixIcon: IconButton(
            tooltip: 'حذف مشتری از این فاکتور',
            icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
            onPressed: () => widget.onChanged(null),
          ),
        ),
        child: Text(
          selected.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      );
    }

    // ---- search state: input + live suggestions + inline add.
    final q = _controller.text.trim();
    final exactExists = _results.any((s) => s.customer.name.trim() == q);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'مشتری',
            hintText: 'نام مشتری را جستجو یا وارد کنید…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        if (_open && q.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _results.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 14, endIndent: 14),
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 17,
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: Text(
                        _initial(_results[i].customer.name),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text(
                      _results[i].customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${faNumber(_results[i].invoiceCount)} فاکتور • '
                      '${ctrl.money(_results[i].totalSpent)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _select(_results[i].customer),
                  ),
                ],
                if (!exactExists) ...[
                  if (_results.isNotEmpty)
                    const Divider(height: 1, indent: 14, endIndent: 14),
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 17,
                      backgroundColor: scheme.secondaryContainer,
                      foregroundColor: scheme.onSecondaryContainer,
                      child: const Icon(Icons.person_add_alt_rounded, size: 19),
                    ),
                    title: Text(
                      'افزودن «$q»',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary),
                    ),
                    subtitle: const Text(
                      'ساخت و انتخاب مشتری جدید',
                      style: TextStyle(fontSize: 12),
                    ),
                    onTap: () => _addNew(q),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
