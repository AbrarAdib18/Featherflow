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

  StockStatus get stockStatus {
    if (stockCount == 0) return StockStatus.outOfStock;
    if (stockCount <= minStock) return StockStatus.lowStock;
    return StockStatus.inStock;
  }

  PharmacyProduct copyWith({int? stockCount, double? price}) =>
      PharmacyProduct(
        id: id,
        name: name,
        category: category,
        stockCount: stockCount ?? this.stockCount,
        minStock: minStock,
        unit: unit,
        price: price ?? this.price,
        manufacturer: manufacturer,
        expiryDate: expiryDate,
        description: description,
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
}
