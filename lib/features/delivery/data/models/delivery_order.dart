enum OrderStatus {
  pending,
  accepted,
  rejected,
  pickedUp,
  onTheWay,
  arrived,
  proofSubmitted,
  proofRejected,
  delivered,
  failed,
  cancelled,
}

enum OrderType { regular, pharmacy }

OrderStatus orderStatusFromApi(String value) => switch (value) {
      'pending' => OrderStatus.pending,
      'accepted' => OrderStatus.accepted,
      'rejected' => OrderStatus.rejected,
      'picked_up' => OrderStatus.pickedUp,
      'on_the_way' => OrderStatus.onTheWay,
      'arrived' => OrderStatus.arrived,
      'proof_submitted' => OrderStatus.proofSubmitted,
      'proof_rejected' => OrderStatus.proofRejected,
      'delivered' => OrderStatus.delivered,
      'failed' => OrderStatus.failed,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.pending,
    };

String orderStatusToApi(OrderStatus status) => switch (status) {
      OrderStatus.pending => 'pending',
      OrderStatus.accepted => 'accepted',
      OrderStatus.rejected => 'rejected',
      OrderStatus.pickedUp => 'picked_up',
      OrderStatus.onTheWay => 'on_the_way',
      OrderStatus.arrived => 'arrived',
      OrderStatus.proofSubmitted => 'proof_submitted',
      OrderStatus.proofRejected => 'proof_rejected',
      OrderStatus.delivered => 'delivered',
      OrderStatus.failed => 'failed',
      OrderStatus.cancelled => 'cancelled',
    };

class OrderItem {
  final String name;
  final int quantity;
  final String? note;

  const OrderItem({required this.name, required this.quantity, this.note});

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        name: json['name']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );
}

/// Human label for a delivery stage (matches the backend STAGE_LABELS).
String orderStageLabel(OrderStatus s) => switch (s) {
      OrderStatus.pending => 'Assigned',
      OrderStatus.accepted => 'Assigned',
      OrderStatus.pickedUp => 'Picked up',
      OrderStatus.onTheWay => 'Out for delivery',
      OrderStatus.arrived => 'Arrived',
      OrderStatus.proofSubmitted => 'Proof under review',
      OrderStatus.proofRejected => 'Proof rejected — resubmit',
      OrderStatus.delivered => 'Completed',
      OrderStatus.failed => 'Failed',
      OrderStatus.rejected => 'Rejected',
      OrderStatus.cancelled => 'Cancelled',
    };

class DeliveryOrder {
  final String id;
  final String pickupAddress;
  final String dropAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropLat;
  final double? dropLng;
  final String customerName;
  final String customerPhone;
  final double distanceKm;
  final OrderType type;
  final OrderStatus status;
  final List<OrderItem> items;
  final String? specialInstructions;
  final bool requiresOtp;
  final double earning;
  final DateTime createdAt;
  final DateTime? assignedAt;
  final DateTime? expiresAt;
  final String? failureReason;
  final String? proofOfDeliveryUrl;
  final DateTime? deliveredAt;
  final bool isColdChain;
  final bool isPrescriptionRequired;
  final String? stageLabel;
  final int proofAttempts;
  final String? proofRejectionReason;
  final String? latestProofUrl;

  const DeliveryOrder({
    required this.id,
    required this.pickupAddress,
    required this.dropAddress,
    this.pickupLat,
    this.pickupLng,
    this.dropLat,
    this.dropLng,
    required this.customerName,
    required this.customerPhone,
    required this.distanceKm,
    required this.type,
    required this.status,
    required this.items,
    this.specialInstructions,
    this.requiresOtp = false,
    required this.earning,
    required this.createdAt,
    this.assignedAt,
    this.expiresAt,
    this.failureReason,
    this.proofOfDeliveryUrl,
    this.deliveredAt,
    this.isColdChain = false,
    this.isPrescriptionRequired = false,
    this.stageLabel,
    this.proofAttempts = 0,
    this.proofRejectionReason,
    this.latestProofUrl,
  });

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] is List ? json['items'] as List : const [];
    return DeliveryOrder(
      id: json['id'].toString(),
      pickupAddress: json['pickup_address']?.toString() ?? '',
      dropAddress: json['delivery_address']?.toString() ?? '',
      pickupLat: (json['pickup_lat'] as num?)?.toDouble(),
      pickupLng: (json['pickup_lng'] as num?)?.toDouble(),
      dropLat: (json['delivery_lat'] as num?)?.toDouble(),
      dropLng: (json['delivery_lng'] as num?)?.toDouble(),
      customerName: json['customer_name']?.toString() ?? '',
      customerPhone: json['customer_phone']?.toString() ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      type: json['order_type'] == 'pharmacy' ? OrderType.pharmacy : OrderType.regular,
      status: orderStatusFromApi(json['status']?.toString() ?? 'pending'),
      items: rawItems
          .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      specialInstructions: json['special_instructions']?.toString(),
      requiresOtp: json['requires_otp'] == true,
      earning: (json['earning'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      assignedAt: json['assigned_at'] != null
          ? DateTime.tryParse(json['assigned_at'].toString())
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      failureReason: json['failure_reason']?.toString(),
      proofOfDeliveryUrl: json['proof_of_delivery_url']?.toString(),
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'].toString())
          : null,
      isColdChain: json['is_cold_chain'] == true,
      isPrescriptionRequired: json['is_prescription_required'] == true,
      stageLabel: json['stage_label']?.toString(),
      proofAttempts: (json['proof_attempts'] as num?)?.toInt() ?? 0,
      proofRejectionReason: json['proof_rejection_reason']?.toString(),
      latestProofUrl: json['latest_proof'] is Map
          ? (json['latest_proof'] as Map)['url']?.toString()
          : null,
    );
  }

  DeliveryOrder copyWith({OrderStatus? status}) => DeliveryOrder(
        id: id,
        pickupAddress: pickupAddress,
        dropAddress: dropAddress,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropLat: dropLat,
        dropLng: dropLng,
        customerName: customerName,
        customerPhone: customerPhone,
        distanceKm: distanceKm,
        type: type,
        status: status ?? this.status,
        items: items,
        specialInstructions: specialInstructions,
        requiresOtp: requiresOtp,
        earning: earning,
        createdAt: createdAt,
        assignedAt: assignedAt,
        expiresAt: expiresAt,
        failureReason: failureReason,
        proofOfDeliveryUrl: proofOfDeliveryUrl,
        deliveredAt: deliveredAt,
        isColdChain: isColdChain,
        isPrescriptionRequired: isPrescriptionRequired,
        stageLabel: stageLabel,
        proofAttempts: proofAttempts,
        proofRejectionReason: proofRejectionReason,
        latestProofUrl: latestProofUrl,
      );
}
