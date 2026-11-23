/// Customer domain model.
///
/// Customers are lightweight identities created *inline* while composing an
/// invoice (see [CustomerField]). Invoices reference the customer by id;
/// they also keep a historical name snapshot so old records stay accurate
/// even after the customer is renamed later.
///
/// Customer names are deliberately NOT unique at the database level — two
/// different people may share the same name (the optional phone number
/// helps distinguish them).
library;

class Customer {
  final int? id;
  final String name;
  final String phone;
  final String notes;
  final DateTime createdAt;

  const Customer({
    this.id,
    required this.name,
    this.phone = '',
    this.notes = '',
    required this.createdAt,
  });

  bool get hasPhone => phone.trim().isNotEmpty;
  bool get hasNotes => notes.trim().isNotEmpty;

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'phone': phone,
        'notes': notes,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

/// A customer together with aggregate statistics.
///
/// [invoiceCount] and [totalSpent] are always computed live from invoice
/// data (never stored counters), so they can never drift out of sync.
class CustomerSummary {
  final Customer customer;
  final int invoiceCount;
  final int totalSpent;
  final int? lastInvoiceAt;

  const CustomerSummary({
    required this.customer,
    this.invoiceCount = 0,
    this.totalSpent = 0,
    this.lastInvoiceAt,
  });
}

/// Thrown when a destructive customer deletion is rejected because
/// historical invoices still reference the customer.
class CustomerHasInvoicesException implements Exception {
  final int invoiceCount;
  const CustomerHasInvoicesException(this.invoiceCount);
}
