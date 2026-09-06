// Models for the real relational pharmacy catalogue (pharmacy_catalogue_medicines)
// and the supplier / expiry / order surfaces around it.

const kMedicineCategories = <String>[
  'antibiotic', 'vaccine', 'vitamin', 'antiparasitic',
  'disinfectant', 'feed_supplement', 'equipment', 'other',
];

const kMedicineUnits = <String>[
  'tablet', 'capsule', 'ml', 'gram', 'kg', 'piece', 'pack', 'bottle',
];

String prettyCategory(String c) => switch (c) {
      'feed_supplement' => 'Feed supplement',
      _ => c.isEmpty ? '' : c[0].toUpperCase() + c.substring(1),
    };

enum MedStock { inStock, lowStock, outOfStock }

class Medicine {
  final String id;
  final String name;
  final String genericName;
  final String manufacturer;
  final String category;
  final bool prescriptionRequired;
  final double price;
  final int stockQuantity;
  final String unit;
  final String packSize;
  final String description;
  final String dosageInstructions;
  final String storageInstructions;
  final bool coldChainRequired;
  final DateTime? expiryDate;
  final String batchNumber;
  final List<String> images;
  final bool isActive;
  final bool isApproved;
  final String approvalStatus; // approved | pending | rejected
  final String approvalRejectedReason;
  final int? expiresInDays;
  final String? expiryAlertLevel; // critical | warning | info | null
  final int viewsCount;
  final int ordersCount;
  final Map<String, dynamic>? pharmacy;

  const Medicine({
    required this.id,
    required this.name,
    required this.genericName,
    required this.manufacturer,
    required this.category,
    required this.prescriptionRequired,
    required this.price,
    required this.stockQuantity,
    required this.unit,
    required this.packSize,
    required this.description,
    required this.dosageInstructions,
    required this.storageInstructions,
    required this.coldChainRequired,
    required this.expiryDate,
    required this.batchNumber,
    required this.images,
    required this.isActive,
    required this.isApproved,
    required this.approvalStatus,
    required this.approvalRejectedReason,
    required this.expiresInDays,
    required this.expiryAlertLevel,
    required this.viewsCount,
    required this.ordersCount,
    this.pharmacy,
  });

  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? '',
        genericName: j['generic_name']?.toString() ?? '',
        manufacturer: j['manufacturer']?.toString() ?? '',
        category: j['category']?.toString() ?? 'other',
        prescriptionRequired: j['prescription_required'] == true,
        price: (j['price'] as num?)?.toDouble() ?? 0,
        stockQuantity: (j['stock_quantity'] as num?)?.toInt() ?? 0,
        unit: j['unit']?.toString() ?? 'piece',
        packSize: j['pack_size']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        dosageInstructions: j['dosage_instructions']?.toString() ?? '',
        storageInstructions: j['storage_instructions']?.toString() ?? '',
        coldChainRequired: j['cold_chain_required'] == true,
        expiryDate: DateTime.tryParse(j['expiry_date']?.toString() ?? ''),
        batchNumber: j['batch_number']?.toString() ?? '',
        images: (j['images'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        isActive: j['is_active'] != false,
        isApproved: j['is_approved'] == true,
        approvalStatus: j['approval_status']?.toString() ??
            (j['is_approved'] == true ? 'approved' : 'pending'),
        approvalRejectedReason: j['approval_rejected_reason']?.toString() ?? '',
        expiresInDays: (j['expires_in_days'] as num?)?.toInt(),
        expiryAlertLevel: j['expiry_alert_level']?.toString(),
        viewsCount: (j['views_count'] as num?)?.toInt() ?? 0,
        ordersCount: (j['orders_count'] as num?)?.toInt() ?? 0,
        pharmacy: (j['pharmacy'] as Map?)?.cast<String, dynamic>(),
      );

  MedStock get stockStatus {
    if (stockQuantity <= 0) return MedStock.outOfStock;
    if (stockQuantity < 10) return MedStock.lowStock;
    return MedStock.inStock;
  }
}

class ExpiryAlert {
  final String alertId;
  final String medicineId;
  final String medicineName;
  final String batchNumber;
  final int expiresInDays;
  final String alertLevel; // critical | warning | info
  final int stockQuantity;
  final bool isAcknowledged;
  final String pharmacyName;

  const ExpiryAlert({
    required this.alertId,
    required this.medicineId,
    required this.medicineName,
    required this.batchNumber,
    required this.expiresInDays,
    required this.alertLevel,
    required this.stockQuantity,
    required this.isAcknowledged,
    required this.pharmacyName,
  });

  factory ExpiryAlert.fromJson(Map<String, dynamic> j) => ExpiryAlert(
        alertId: j['alert_id'].toString(),
        medicineId: j['medicine_id']?.toString() ?? '',
        medicineName: j['medicine_name']?.toString() ?? '',
        batchNumber: j['batch_number']?.toString() ?? '',
        expiresInDays: (j['expires_in_days'] as num?)?.toInt() ?? 0,
        alertLevel: j['alert_level']?.toString() ?? 'info',
        stockQuantity: (j['stock_quantity'] as num?)?.toInt() ?? 0,
        isAcknowledged: j['is_acknowledged'] == true,
        pharmacyName: j['pharmacy_name']?.toString() ?? '',
      );
}

class Supplier {
  final String id;
  final String supplierName;
  final String contactPerson;
  final String phone;
  final String email;
  final String address;
  final String productsSupplied;
  final String paymentTerms;
  final bool isActive;

  const Supplier({
    required this.id,
    required this.supplierName,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.address,
    required this.productsSupplied,
    required this.paymentTerms,
    required this.isActive,
  });

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: (j['supplier_id'] ?? j['id']).toString(),
        supplierName: j['supplier_name']?.toString() ?? '',
        contactPerson: j['contact_person']?.toString() ?? '',
        phone: j['phone']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        address: j['address']?.toString() ?? '',
        productsSupplied: j['products_supplied']?.toString() ?? '',
        paymentTerms: j['payment_terms']?.toString() ?? '',
        isActive: j['is_active'] != false,
      );
}

class CatalogueOrderItem {
  final String medicineId;
  final String name;
  final int quantity;
  final double unitPrice;
  final bool prescriptionRequired;
  final bool coldChainRequired;

  const CatalogueOrderItem({
    required this.medicineId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.prescriptionRequired,
    required this.coldChainRequired,
  });

  factory CatalogueOrderItem.fromJson(Map<String, dynamic> j) => CatalogueOrderItem(
        medicineId: (j['medicine_id'] ?? j['product_id']).toString(),
        name: j['product_name']?.toString() ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0,
        prescriptionRequired: j['prescription_required'] == true,
        coldChainRequired: j['cold_chain_required'] == true,
      );

  double get subtotal => quantity * unitPrice;
}

class RiderInfo {
  final String name;
  final String phone;
  final double rating;
  final String deliveryStatus;
  final String otpCode;

  const RiderInfo({
    required this.name,
    required this.phone,
    required this.rating,
    required this.deliveryStatus,
    required this.otpCode,
  });

  factory RiderInfo.fromJson(Map<String, dynamic> j) => RiderInfo(
        name: j['rider_name']?.toString() ?? '',
        phone: j['rider_phone']?.toString() ?? '',
        rating: (j['rider_rating'] as num?)?.toDouble() ?? 0,
        deliveryStatus: j['delivery_status']?.toString() ?? '',
        otpCode: j['otp_code']?.toString() ?? '',
      );
}

// Order status the app speaks (translated from the JSON bridge server-side).
enum PharmacyOrderStatus {
  pending, preparing, readyForDelivery, outForDelivery, delivered, cancelled, refunded, deliveryFailed;

  static PharmacyOrderStatus parse(String raw) => switch (raw) {
        'pending' => pending,
        'confirmed' || 'preparing' || 'processing' => preparing,
        'ready_for_delivery' || 'ready_for_pickup' || 'shipped' => readyForDelivery,
        'out_for_delivery' => outForDelivery,
        'delivered' => delivered,
        'cancelled' => cancelled,
        'refunded' => refunded,
        'delivery_failed' => deliveryFailed,
        _ => pending,
      };

  String get label => switch (this) {
        pending => 'Pending',
        preparing => 'Preparing',
        readyForDelivery => 'Ready',
        outForDelivery => 'Out for delivery',
        delivered => 'Delivered',
        cancelled => 'Cancelled',
        refunded => 'Refunded',
        deliveryFailed => 'Delivery failed',
      };
}

class CatalogueOrder {
  final String id;
  final String orderNumber;
  final String farmerName;
  final String farmerPhone;
  final String farmName;
  final PharmacyOrderStatus status;
  final String paymentStatus;
  final String paymentMethod;
  final String deliveryMethod;
  final double deliveryFee;
  final double subtotal;
  final double totalAmount;
  final String deliveryAddress;
  final String? prescriptionImage;
  final String notes;
  final int itemsCount;
  final bool requiresPrescription;
  final bool requiresColdChain;
  final DateTime? createdAt;
  final List<CatalogueOrderItem> items;
  final List<Map<String, dynamic>> statusHistory;
  final RiderInfo? rider;
  final List<Map<String, dynamic>> timeline;

  const CatalogueOrder({
    required this.id,
    required this.orderNumber,
    required this.farmerName,
    required this.farmerPhone,
    required this.farmName,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.deliveryMethod,
    required this.deliveryFee,
    required this.subtotal,
    required this.totalAmount,
    required this.deliveryAddress,
    required this.prescriptionImage,
    required this.notes,
    required this.itemsCount,
    required this.requiresPrescription,
    required this.requiresColdChain,
    required this.createdAt,
    required this.items,
    required this.statusHistory,
    required this.rider,
    required this.timeline,
  });

  factory CatalogueOrder.fromJson(Map<String, dynamic> j) => CatalogueOrder(
        id: (j['order_id'] ?? j['id']).toString(),
        orderNumber: j['order_number']?.toString() ?? '',
        farmerName: j['farmer_name']?.toString() ?? '',
        farmerPhone: j['farmer_phone']?.toString() ?? '',
        farmName: j['farm_name']?.toString() ?? '',
        status: PharmacyOrderStatus.parse(j['status']?.toString() ?? 'pending'),
        paymentStatus: j['payment_status']?.toString() ?? 'pending',
        paymentMethod: j['payment_method']?.toString() ?? 'cod',
        deliveryMethod: j['delivery_method']?.toString() ?? 'delivery',
        deliveryFee: (j['delivery_fee'] as num?)?.toDouble() ?? 0,
        subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0,
        totalAmount: (j['total_amount'] as num?)?.toDouble() ?? 0,
        deliveryAddress: j['delivery_address']?.toString() ?? '',
        prescriptionImage: j['prescription_image']?.toString(),
        notes: j['notes']?.toString() ?? '',
        itemsCount: (j['items_count'] as num?)?.toInt() ??
            (j['items'] as List?)?.length ?? 0,
        requiresPrescription: j['requires_prescription'] == true,
        requiresColdChain: j['requires_cold_chain'] == true,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
        items: (j['items'] as List? ?? const [])
            .map((e) => CatalogueOrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        statusHistory: (j['status_history'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        rider: (j['delivery'] is Map)
            ? RiderInfo.fromJson(Map<String, dynamic>.from(j['delivery'] as Map))
            : null,
        timeline: (j['timeline'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

class InventorySummary {
  final int totalProducts;
  final int lowStockCount;
  final int outOfStockCount;
  final int expiringSoonCount;
  final int criticalExpiryCount;
  final int pendingApprovalCount;
  final double stockValue;

  const InventorySummary({
    this.totalProducts = 0,
    this.lowStockCount = 0,
    this.outOfStockCount = 0,
    this.expiringSoonCount = 0,
    this.criticalExpiryCount = 0,
    this.pendingApprovalCount = 0,
    this.stockValue = 0,
  });

  factory InventorySummary.fromJson(Map<String, dynamic> j) => InventorySummary(
        totalProducts: (j['total_products'] as num?)?.toInt() ?? 0,
        lowStockCount: (j['low_stock_count'] as num?)?.toInt() ?? 0,
        outOfStockCount: (j['out_of_stock_count'] as num?)?.toInt() ?? 0,
        expiringSoonCount: (j['expiring_soon_count'] as num?)?.toInt() ?? 0,
        criticalExpiryCount: (j['critical_expiry_count'] as num?)?.toInt() ?? 0,
        pendingApprovalCount: (j['pending_approval_count'] as num?)?.toInt() ?? 0,
        stockValue: (j['stock_value'] as num?)?.toDouble() ?? 0,
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

  factory PharmacyProfile.fromJson(Map<String, dynamic> j) => PharmacyProfile(
        name: j['name']?.toString() ?? '',
        licenseNumber: j['license_number']?.toString() ?? '',
        location: j['location']?.toString() ?? j['address']?.toString() ?? '',
        phone: j['phone']?.toString() ?? '',
      );

  static const empty =
      PharmacyProfile(name: 'Pharmacy', licenseNumber: '', location: '', phone: '');
}
