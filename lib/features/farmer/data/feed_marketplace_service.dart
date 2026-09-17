import 'farm_management_service.dart';

/// A catalogue product from the admin-approved feed catalogue
/// (backend `feed_catalogue` app). Farmers can only ever select from these —
/// there is no free-text product entry anywhere in this flow.
class FeedMarketProduct {
  final String id;
  final String companyId;
  final String companyName;
  final String companyLogoUrl;
  final String productName;
  final String brand;
  final String feedType;
  final String birdType;
  final String description;
  final String ingredients;
  final Map<String, dynamic> nutritionalInfo;
  final String unit;
  final double price;
  final int stockQuantity;
  final int minOrderQuantity;
  final String imageUrl;
  final List<String> galleryUrls;
  final bool inStock;

  const FeedMarketProduct({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.companyLogoUrl,
    required this.productName,
    required this.brand,
    required this.feedType,
    required this.birdType,
    required this.description,
    required this.ingredients,
    required this.nutritionalInfo,
    required this.unit,
    required this.price,
    required this.stockQuantity,
    required this.minOrderQuantity,
    required this.imageUrl,
    required this.galleryUrls,
    required this.inStock,
  });

  factory FeedMarketProduct.fromJson(Map<String, dynamic> j) => FeedMarketProduct(
        id: j['id']?.toString() ?? '',
        companyId: j['company_id']?.toString() ?? '',
        companyName: j['company_name']?.toString() ?? '',
        companyLogoUrl: j['company_logo_url']?.toString() ?? '',
        productName: j['product_name']?.toString() ?? '',
        brand: j['brand']?.toString() ?? '',
        feedType: j['feed_type']?.toString() ?? '',
        birdType: j['bird_type']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        ingredients: j['ingredients']?.toString() ?? '',
        nutritionalInfo: j['nutritional_info'] is Map
            ? Map<String, dynamic>.from(j['nutritional_info'] as Map)
            : const {},
        unit: j['unit']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        stockQuantity: (j['stock_quantity'] as num?)?.toInt() ?? 0,
        minOrderQuantity: (j['min_order_quantity'] as num?)?.toInt() ?? 1,
        imageUrl: j['image_url']?.toString() ?? '',
        galleryUrls: j['gallery_urls'] is List
            ? (j['gallery_urls'] as List).map((e) => e.toString()).toList()
            : const [],
        inStock: j['in_stock'] == true,
      );
}

class FeedCartLine {
  final FeedMarketProduct product;
  int quantity;
  FeedCartLine(this.product, this.quantity);
  double get lineTotal => product.price * quantity;
}

class FeedMarketplaceFilters {
  final String? query;
  final String? birdType;
  final String? feedType;
  final String? companyId;
  final double? minPrice;
  final double? maxPrice;
  final bool inStockOnly;

  const FeedMarketplaceFilters({
    this.query,
    this.birdType,
    this.feedType,
    this.companyId,
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
  });

  bool get isActive =>
      birdType != null || feedType != null || companyId != null ||
      minPrice != null || maxPrice != null || inStockOnly;

  FeedMarketplaceFilters copyWith({
    String? query,
    String? Function()? birdType,
    String? Function()? feedType,
    String? Function()? companyId,
    double? Function()? minPrice,
    double? Function()? maxPrice,
    bool? inStockOnly,
  }) =>
      FeedMarketplaceFilters(
        query: query ?? this.query,
        birdType: birdType != null ? birdType() : this.birdType,
        feedType: feedType != null ? feedType() : this.feedType,
        companyId: companyId != null ? companyId() : this.companyId,
        minPrice: minPrice != null ? minPrice() : this.minPrice,
        maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
        inStockOnly: inStockOnly ?? this.inStockOnly,
      );
}

class FeedMarketplaceService {
  static Future<List<FeedMarketProduct>> search({
    String? query,
    String? birdType,
    String? feedType,
    String? companyId,
    double? minPrice,
    double? maxPrice,
    bool inStockOnly = false,
  }) async {
    final params = <String>[];
    if (query != null && query.isNotEmpty) params.add('search=${Uri.encodeQueryComponent(query)}');
    if (birdType != null) params.add('bird_type=$birdType');
    if (feedType != null) params.add('feed_type=$feedType');
    if (companyId != null) params.add('company_id=$companyId');
    if (minPrice != null) params.add('min_price=$minPrice');
    if (maxPrice != null) params.add('max_price=$maxPrice');
    if (inStockOnly) params.add('in_stock_only=true');
    final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
    final res = await FarmManagementService.get('farmers/feed-catalogue/products$qs');
    return ((res['results'] as List?) ?? const [])
        .map((e) => FeedMarketProduct.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> companies() async {
    final res = await FarmManagementService.get('farmers/feed-catalogue/products');
    // Farmers have no dedicated companies endpoint — derive the distinct
    // company list from approved products so the filter sheet can offer a
    // brand picker without a new backend surface.
    final seen = <String, Map<String, dynamic>>{};
    for (final e in (res['results'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(e as Map);
      seen[m['company_id'].toString()] = {'id': m['company_id'], 'name': m['company_name']};
    }
    return seen.values.toList();
  }

  static Future<List<Map<String, dynamic>>> myOrders() async {
    final res = await FarmManagementService.get('farmers/feed-catalogue/orders');
    return ((res['results'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Places an order. The server resolves every price/name/availability from
  /// the catalogue itself — [cart] only ever sends product ids + quantities.
  static Future<Map<String, dynamic>> placeOrder({
    required List<FeedCartLine> cart,
    required String deliveryAddress,
    double? latitude,
    double? longitude,
    required String paymentMethod,
    String? contactPhone,
    String? notes,
  }) =>
      FarmManagementService.post('farmers/feed-catalogue/orders', {
        'items': cart.map((l) => {'product_id': l.product.id, 'quantity': l.quantity}).toList(),
        'delivery_address': deliveryAddress,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'payment_method': paymentMethod,
        if (contactPhone != null) 'contact_phone': contactPhone,
        if (notes != null) 'notes': notes,
      });

  static Future<Map<String, dynamic>> cancelOrder(String orderId) =>
      FarmManagementService.post('farmers/feed-catalogue/orders/$orderId/cancel', const {});
}
