enum ProductCategory { medicines, vaccines, supplements, equipment }

enum StockStatus { inStock, lowStock, outOfStock }

enum OrderStatus { pending, processing, shipped, delivered, cancelled }

class PharmacyProduct {
  final String id;
  final String name;
  final ProductCategory category;
  final int stockCount;
  final int minStock;
  final String unit;
  final double price;
  final String manufacturer;
  final DateTime expiryDate;
  final String? description;

  const PharmacyProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.stockCount,
    required this.minStock,
    required this.unit,
    required this.price,
    required this.manufacturer,
    required this.expiryDate,
    this.description,
  });

  factory PharmacyProduct.fromJson(Map<String, dynamic> json) =>
      PharmacyProduct(
        id: json['id'].toString(),
        name: json['name'].toString(),
        category: ProductCategory.values.byName(json['category'].toString()),
        stockCount: (json['stock_count'] as num).toInt(),
        minStock: (json['min_stock'] as num).toInt(),
        unit: json['unit'].toString(),
        price: (json['price'] as num).toDouble(),
        manufacturer: json['manufacturer'].toString(),
        expiryDate: DateTime.parse(json['expiry_date'].toString()),
        description: json['description']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'stock_count': stockCount,
        'min_stock': minStock,
        'unit': unit,
        'price': price,
        'manufacturer': manufacturer,
        'expiry_date': expiryDate.toIso8601String().split('T').first,
        'description': description,
      };

  StockStatus get stockStatus {
    if (stockCount == 0) return StockStatus.outOfStock;
    if (stockCount <= minStock) return StockStatus.lowStock;
    return StockStatus.inStock;
  }

  PharmacyProduct copyWith(
          {String? name,
          ProductCategory? category,
          int? stockCount,
          int? minStock,
          String? unit,
          double? price,
          String? manufacturer,
          DateTime? expiryDate,
          String? description}) =>
      PharmacyProduct(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        stockCount: stockCount ?? this.stockCount,
        minStock: minStock ?? this.minStock,
        unit: unit ?? this.unit,
        price: price ?? this.price,
        manufacturer: manufacturer ?? this.manufacturer,
        expiryDate: expiryDate ?? this.expiryDate,
        description: description ?? this.description,
      );
}

class OrderItem {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;

  const OrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        productId: json['product_id'].toString(),
        productName: json['product_name'].toString(),
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unit_price'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice
      };

  double get subtotal => quantity * unitPrice;
}

class PharmacyOrder {
  final String id;
  final String orderNumber;
  final String farmerId;
  final String farmerName;
  final String farmName;
  final List<OrderItem> items;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final String? notes;

  const PharmacyOrder({
    required this.id,
    required this.orderNumber,
    required this.farmerId,
    required this.farmerName,
    required this.farmName,
    required this.items,
    required this.status,
    required this.createdAt,
    this.deliveredAt,
    this.notes,
  });

  factory PharmacyOrder.fromJson(Map<String, dynamic> json) => PharmacyOrder(
        id: json['id'].toString(),
        orderNumber: json['order_number'].toString(),
        farmerId: json['farmer_id'].toString(),
        farmerName: json['farmer_name'].toString(),
        farmName: json['farm_name'].toString(),
        items: (json['items'] as List)
            .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        status: OrderStatus.values.byName(json['status'].toString()),
        createdAt: DateTime.parse(json['created_at'].toString()),
        deliveredAt: json['delivered_at'] == null
            ? null
            : DateTime.parse(json['delivered_at'].toString()),
        notes: json['notes']?.toString(),
      );

  double get totalAmount => items.fold(0.0, (sum, item) => sum + item.subtotal);

  PharmacyOrder copyWith({OrderStatus? status, DateTime? deliveredAt}) =>
      PharmacyOrder(
        id: id,
        orderNumber: orderNumber,
        farmerId: farmerId,
        farmerName: farmerName,
        farmName: farmName,
        items: items,
        status: status ?? this.status,
        createdAt: createdAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        notes: notes,
      );
}

class PharmacyProfile {
  final String name;
  final String licenseNumber;
  final String location;
  final String phone;

  const PharmacyProfile({
    required this.name,
    required this.licenseNumber,
    required this.location,
    required this.phone,
  });

  factory PharmacyProfile.fromJson(Map<String, dynamic> json) =>
      PharmacyProfile(
        name: json['name']?.toString() ?? '',
        licenseNumber: json['license_number']?.toString() ?? '',
        location: json['location']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
      );
}
