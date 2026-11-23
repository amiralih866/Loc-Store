/// Product & variant domain models.
library;

/// Stock health of a variant (or whole product).
enum StockStatus { ok, low, out }

/// Low-stock threshold logic — centralized business rule.
StockStatus stockStatusFor(int stock, int lowThreshold) {
  if (stock <= 0) return StockStatus.out;
  if (stock <= lowThreshold) return StockStatus.low;
  return StockStatus.ok;
}

class Product {
  final int? id;
  final String name;
  final String color;
  final int defaultPrice;
  final String? imagePath;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    this.id,
    required this.name,
    required this.color,
    required this.defaultPrice,
    this.imagePath,
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int?,
        name: m['name'] as String,
        color: (m['color'] as String?) ?? '',
        defaultPrice: (m['default_price'] as int?) ?? 0,
        imagePath: m['image_path'] as String?,
        active: ((m['active'] as int?) ?? 1) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'color': color,
        'default_price': defaultPrice,
        'image_path': imagePath,
        'active': active ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  Product copyWith({
    int? id,
    String? name,
    String? color,
    int? defaultPrice,
    String? imagePath,
    bool clearImage = false,
    bool? active,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        defaultPrice: defaultPrice ?? this.defaultPrice,
        imagePath: clearImage ? null : (imagePath ?? this.imagePath),
        active: active ?? this.active,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ProductVariant {
  final int? id;
  final int productId;
  final String name;
  final int? customPrice; // null => fallback to product default price
  final int stock;
  final DateTime createdAt;

  const ProductVariant({
    this.id,
    required this.productId,
    required this.name,
    this.customPrice,
    required this.stock,
    required this.createdAt,
  });

  factory ProductVariant.fromMap(Map<String, Object?> m) => ProductVariant(
        id: m['id'] as int?,
        productId: m['product_id'] as int,
        name: m['name'] as String,
        customPrice: m['price'] as int?,
        stock: (m['stock'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'name': name,
        'price': customPrice,
        'stock': stock,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

/// Aggregate info about a product for list screens.
class ProductSummary {
  final Product product;
  final int totalStock;
  final int variantCount;
  final int lowCount;
  final int outCount;
  final int usageCount; // number of historical invoice items referencing it

  const ProductSummary({
    required this.product,
    required this.totalStock,
    required this.variantCount,
    required this.lowCount,
    required this.outCount,
    required this.usageCount,
  });

  StockStatus statusFor(int lowThreshold) {
    if (totalStock <= 0) return StockStatus.out;
    if (lowCount > 0 || outCount > 0) return StockStatus.low;
    return StockStatus.ok;
  }
}

/// Form input for creating/updating variants.
class VariantInput {
  final int? id; // null => new variant
  final String name;
  final int? customPrice; // null => use product default
  final int stock;

  const VariantInput({
    this.id,
    required this.name,
    this.customPrice,
    required this.stock,
  });
}

/// A variant with its parent product info (for low-stock lists).
class VariantWithProduct {
  final ProductVariant variant;
  final Product product;

  const VariantWithProduct({required this.variant, required this.product});
}

/// Resolves the effective unit price — THE pricing rule of the app:
/// variant custom price wins, otherwise product default price.
int resolveUnitPrice({
  required int productDefault,
  int? variantCustom,
}) =>
    variantCustom ?? productDefault;
