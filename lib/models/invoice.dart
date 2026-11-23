/// Invoice domain models.
///
/// Invoice items carry full *snapshots* (name/color/variant/unit price) so
/// historical invoices stay accurate even if products change or are removed.
library;

/// Payment status of an invoice — strictly limited to these two states;
/// no other payment states exist in the system.
enum InvoiceStatus { paid, unpaid }

extension InvoiceStatusX on InvoiceStatus {
  /// Exact value persisted in the SQLite column (`status`).
  String get storage => this == InvoiceStatus.paid ? 'Paid' : 'Unpaid';

  /// Persian label used everywhere in the UI and on the invoice image.
  String get faLabel =>
      this == InvoiceStatus.paid ? 'پرداخت شده' : 'پرداخت نشده';

  /// Parses a stored value; unknown/null values fall back to [InvoiceStatus
  /// .unpaid] — the default of every newly created invoice.
  static InvoiceStatus parse(Object? raw) =>
      raw == 'Paid' ? InvoiceStatus.paid : InvoiceStatus.unpaid;
}

class Invoice {
  final int? id;
  final int number;

  /// Linked customer (null for invoices created before customers existed,
  /// or legacy walk-in records).
  final int? customerId;

  /// Historical name snapshot taken at sale time — never changes when the
  /// customer profile is edited later.
  final String customerName;
  final int total;
  final DateTime createdAt;

  /// Payment status, selected at creation time and editable later.
  final InvoiceStatus status;

  /// Optional free-text description/notes belonging to the invoice itself.
  final String description;
  final int itemCount;
  final List<InvoiceItem> items;

  const Invoice({
    this.id,
    required this.number,
    this.customerId,
    required this.customerName,
    required this.total,
    required this.createdAt,
    this.status = InvoiceStatus.unpaid,
    this.description = '',
    this.itemCount = 0,
    this.items = const [],
  });

  factory Invoice.fromMap(Map<String, Object?> m) => Invoice(
        id: m['id'] as int?,
        number: m['number'] as int,
        customerId: m['customer_id'] as int?,
        customerName: (m['customer_name'] as String?) ?? '',
        total: (m['total'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        status: InvoiceStatusX.parse(m['status']),
        description: (m['description'] as String?) ?? '',
        itemCount: (m['item_count'] as int?) ?? 0,
      );
}

class InvoiceItem {
  final int? id;
  final int invoiceId;
  final int? productId;
  final int? variantId;
  final String productName; // snapshot
  final String productColor; // snapshot
  final String variantName; // snapshot
  final int quantity;
  final int unitPrice; // snapshot — never changes after creation
  final int total;

  const InvoiceItem({
    this.id,
    required this.invoiceId,
    this.productId,
    this.variantId,
    required this.productName,
    required this.productColor,
    required this.variantName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  factory InvoiceItem.fromMap(Map<String, Object?> m) => InvoiceItem(
        id: m['id'] as int?,
        invoiceId: m['invoice_id'] as int,
        productId: m['product_id'] as int?,
        variantId: m['variant_id'] as int?,
        productName: m['product_name'] as String,
        productColor: (m['product_color'] as String?) ?? '',
        variantName: (m['variant_name'] as String?) ?? '',
        quantity: (m['quantity'] as int?) ?? 0,
        unitPrice: (m['unit_price'] as int?) ?? 0,
        total: (m['total'] as int?) ?? 0,
      );
}

/// An item inside the *draft* invoice while the user is composing it.
class InvoiceDraftItem {
  final int variantId;
  final int productId;
  final String productName;
  final String productColor;
  final String variantName;
  final int quantity;
  final int unitPrice;
  final int availableStock;

  const InvoiceDraftItem({
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.productColor,
    required this.variantName,
    required this.quantity,
    required this.unitPrice,
    required this.availableStock,
  });

  int get lineTotal => quantity * unitPrice;

  InvoiceDraftItem copyWith({int? quantity}) => InvoiceDraftItem(
        variantId: variantId,
        productId: productId,
        productName: productName,
        productColor: productColor,
        variantName: variantName,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice,
        availableStock: availableStock,
      );
}

/// Exceptions used to communicate business-rule failures in user terms.
class InsufficientStockException implements Exception {
  final String productName;
  final String variantName;
  final int available;
  const InsufficientStockException({
    required this.productName,
    required this.variantName,
    required this.available,
  });
}

class VariantNotFoundException implements Exception {
  const VariantNotFoundException();
}

class DuplicateVariantException implements Exception {
  final String name;
  const DuplicateVariantException(this.name);
}

class EmptyInvoiceException implements Exception {
  const EmptyInvoiceException();
}

/// One entry of a variant's sales history on the Product Details screen —
/// a pointer to the invoice that sold this variant. Everything shown here
/// comes from invoice/invoice-item data; nothing is stored on the product.
class VariantSaleEntry {
  final int invoiceId;
  final int invoiceNumber;
  final String customerName;
  final int quantity;
  final DateTime createdAt;
  final InvoiceStatus status;

  const VariantSaleEntry({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.customerName,
    required this.quantity,
    required this.createdAt,
    required this.status,
  });
}

/// Sales history of ONE variant/type of a product, grouped live from
/// invoice-item rows — the "sold" total is never a stored counter.
class VariantSalesGroup {
  final String variantName;
  final int totalSold;
  final List<VariantSaleEntry> entries;

  const VariantSalesGroup({
    required this.variantName,
    required this.totalSold,
    required this.entries,
  });
}
