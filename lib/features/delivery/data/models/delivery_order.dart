enum OrderStatus {
  pending,
  accepted,
  pickedUp,
  onTheWay,
  delivered,
  failed,
  cancelled,
}

enum OrderType { regular, pharmacy }

class OrderItem {
  final String name;
  final int quantity;
  final String? note;

  const OrderItem({required this.name, required this.quantity, this.note});
}

class DeliveryOrder {
  final String id;
  final String pickupAddress;
  final String dropAddress;
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

  const DeliveryOrder({
    required this.id,
    required this.pickupAddress,
    required this.dropAddress,
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
  });

  DeliveryOrder copyWith({OrderStatus? status}) => DeliveryOrder(
        id: id,
        pickupAddress: pickupAddress,
        dropAddress: dropAddress,
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
      );
}
