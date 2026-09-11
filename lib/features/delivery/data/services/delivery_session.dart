import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/network/user_updates_service.dart';
import '../models/delivery_earnings.dart';
import '../models/delivery_order.dart';
import 'delivery_api_service.dart';

class DeliverySession extends ChangeNotifier {
  DeliverySession._() {
    AuthService.instance.addListener(_loadRegisteredProfile);
    // Real-time: an admin assigning an order pokes this session so the new
    // request shows up without waiting for the next scheduled poll.
    UserUpdatesService.instance.addRefreshHook(() {
      if (_pollTimer != null) refresh(silent: true);
    });
    _loadRegisteredProfile();
  }
  static final DeliverySession instance = DeliverySession._();

  bool isLoading = false;
  String? errorMessage;
  Timer? _pollTimer;
  Timer? _locationTimer;
  bool _locationTrackingActive = false;

  bool isOnline = false;
  String currentStatus = 'offline';
  double rating = 0;
  int pendingRequestsCount = 0;
  int completedTodayCount = 0;
  double todayEarnings = 0;
  String attendanceStatus = 'not_marked';
  bool checkedIn = false;
  DeliveryOrder? activeOrder;

  List<DeliveryOrder> _requests = [];
  List<DeliveryOrder> _orders = [];
  DeliveryEarnings earnings = DeliveryEarnings.empty;
  List<Map<String, dynamic>> attendanceRecords = [];

  List<DeliveryOrder> get requests => List.unmodifiable(_requests);
  List<DeliveryOrder> get orders => List.unmodifiable(_orders);
  List<DeliveryOrder> get completedOrders => _orders
      .where((o) =>
          o.status == OrderStatus.delivered &&
          _isToday(o.createdAt))
      .toList();
  List<DeliveryOrder> get historyOrders => _orders.where((o) => const {
        OrderStatus.delivered,
        OrderStatus.failed,
        OrderStatus.cancelled,
        OrderStatus.rejected,
      }.contains(o.status)).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  /// Kick a load if one has never happened. The AuthService listener only fires
  /// on an in-session login (saveSession), not when the session is restored
  /// from storage on a hard refresh / app restart — so a screen that boots
  /// straight onto the delivery dashboard must call this from initState or it
  /// would sit on an empty/loading state forever.
  void ensureStarted() {
    if (_pollTimer == null) _loadRegisteredProfile();
  }

  Future<void> _loadRegisteredProfile() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (session == null) {
      _pollTimer?.cancel();
      return;
    }
    if (!session.user.roles.any((role) => role.toLowerCase() == 'delivery')) {
      return;
    }
    await refresh();
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => refresh(silent: true));
  }

  Future<void> refresh({bool silent = false}) async {
    if (isLoading) return;
    isLoading = true;
    errorMessage = null;
    if (!silent) notifyListeners();
    try {
      final results = await Future.wait([
        DeliveryApiService.dashboard(),
        DeliveryApiService.requests(),
        DeliveryApiService.orders(),
        DeliveryApiService.earnings(),
        DeliveryApiService.attendanceHistory(),
      ]);
      final dashboard = results[0] as Map<String, dynamic>;
      isOnline = dashboard['is_online'] == true;
      currentStatus = dashboard['current_status']?.toString() ?? 'offline';
      rating = (dashboard['rating'] as num?)?.toDouble() ?? 0;
      pendingRequestsCount = (dashboard['pending_requests'] as num?)?.toInt() ?? 0;
      completedTodayCount = (dashboard['completed_today'] as num?)?.toInt() ?? 0;
      todayEarnings = (dashboard['today_earnings'] as num?)?.toDouble() ?? 0;
      attendanceStatus = dashboard['attendance_status']?.toString() ?? 'not_marked';
      checkedIn = dashboard['checked_in'] == true;
      final activeOrderJson = dashboard['active_order'];
      activeOrder = activeOrderJson is Map
          ? DeliveryOrder.fromJson(Map<String, dynamic>.from(activeOrderJson))
          : null;
      _requests = results[1] as List<DeliveryOrder>;
      _orders = results[2] as List<DeliveryOrder>;
      earnings = DeliveryEarnings.fromJson(results[3] as Map<String, dynamic>);
      attendanceRecords = results[4] as List<Map<String, dynamic>>;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      _syncLocationTracking();
      notifyListeners();
    }
  }

  void _syncLocationTracking() {
    if (isOnline && !_locationTrackingActive) {
      _locationTrackingActive = true;
      _pushLocation();
      _locationTimer?.cancel();
      _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) => _pushLocation());
    } else if (!isOnline && _locationTrackingActive) {
      _locationTrackingActive = false;
      _locationTimer?.cancel();
      _locationTimer = null;
    }
  }

  Future<void> _pushLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await DeliveryApiService.pushLocation(position.latitude, position.longitude);
    } catch (_) {
      // Best-effort: location pings are non-critical, never surface as a user-facing error.
    }
  }

  Future<Map<String, dynamic>> fetchRoute(String orderId) =>
      DeliveryApiService.route(orderId);

  Future<String> uploadProof(List<int> bytes, String filename) =>
      DeliveryApiService.uploadProof(bytes, filename);

  Future<List<DeliveryOrder>> fetchHistory(
          {String? status, int limit = 20, int offset = 0}) =>
      DeliveryApiService.orders(status: status, limit: limit, offset: offset);

  Future<void> toggleOnline() async {
    final next = !isOnline;
    final original = isOnline;
    isOnline = next;
    currentStatus = next ? 'active' : 'offline';
    notifyListeners();
    try {
      final result = await DeliveryApiService.setAvailability(isOnline: next);
      isOnline = result['is_online'] == true;
      currentStatus = result['current_status']?.toString() ?? currentStatus;
    } catch (error) {
      isOnline = original;
      errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
    _syncLocationTracking();
    notifyListeners();
  }

  Future<void> setOnBreak(bool onBreak) async {
    final result = await DeliveryApiService.setAvailability(
        currentStatus: onBreak ? 'on_break' : 'active');
    currentStatus = result['current_status']?.toString() ?? currentStatus;
    isOnline = result['is_online'] == true;
    notifyListeners();
  }

  Future<void> respondToRequest(String orderId, bool accept) async {
    final order = _requests.firstWhere((o) => o.id == orderId);
    _requests.removeWhere((o) => o.id == orderId);
    notifyListeners();
    try {
      final updated = await DeliveryApiService.respond(orderId, accept);
      if (accept) {
        activeOrder = updated;
        _orders.insert(0, updated);
      }
    } catch (error) {
      _requests.add(order);
      errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? otpCode,
    String? proofOfDeliveryUrl,
    String? failureReason,
  }) async {
    final original = activeOrder;
    if (activeOrder?.id == orderId) {
      activeOrder = activeOrder!.copyWith(status: status);
    }
    notifyListeners();
    try {
      final updated = await DeliveryApiService.updateStatus(
        orderId, status,
        otpCode: otpCode,
        proofOfDeliveryUrl: proofOfDeliveryUrl,
        failureReason: failureReason,
      );
      final idx = _orders.indexWhere((o) => o.id == orderId);
      if (idx >= 0) {
        _orders[idx] = updated;
      } else {
        _orders.insert(0, updated);
      }
      if (status == OrderStatus.delivered || status == OrderStatus.failed) {
        activeOrder = null;
      } else {
        activeOrder = updated;
      }
    } catch (error) {
      activeOrder = original;
      errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
    notifyListeners();
    unawaited(refresh(silent: true));
  }

  Future<void> checkIn() async {
    await DeliveryApiService.checkIn();
    await refresh(silent: true);
  }

  Future<void> checkOut() async {
    await DeliveryApiService.checkOut();
    await refresh(silent: true);
  }
}
