import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../router/app_router.dart';

class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthUser {
  AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.roles,
    required this.accountStatus,
    required this.phone,
    required this.presentAddress,
    required this.dateOfBirth,
    required this.profileData,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      fullName:
          json['full_name']?.toString() ?? json['fullName']?.toString() ?? '',
      roles: (json['roles'] as List<dynamic>? ?? [])
          .map((role) => role.toString())
          .toList(),
      accountStatus: json['account_status']?.toString() ?? 'pending',
      phone: json['phone']?.toString() ?? '',
      presentAddress: json['present_address']?.toString() ?? '',
      dateOfBirth: json['date_of_birth']?.toString() ?? '',
      profileData: Map<String, dynamic>.from(
          json['profile_data'] as Map? ?? const <String, dynamic>{}),
    );
  }

  final String id;
  final String email;
  final String fullName;
  final List<String> roles;
  final String accountStatus;
  final String phone;
  final String presentAddress;
  final String dateOfBirth;
  final Map<String, dynamic> profileData;

  String profileValue(String key, [String fallback = '']) {
    final value = profileData[key];
    return value == null || value.toString().trim().isEmpty
        ? fallback
        : value.toString();
  }
}

class AuthSession {
  AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access']?.toString() ?? '',
      refreshToken: json['refresh']?.toString() ?? '',
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
    );
  }

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  Map<String, dynamic> toJson() => {
        'access': accessToken,
        'refresh': refreshToken,
        'user': {
          'id': user.id,
          'email': user.email,
          'full_name': user.fullName,
          'roles': user.roles,
          'account_status': user.accountStatus,
          'phone': user.phone,
          'present_address': user.presentAddress,
          'date_of_birth': user.dateOfBirth,
          'profile_data': user.profileData,
        },
      };
}

class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  AuthSession? _currentSession;
  AuthSession? get currentSession => _currentSession;

  static const _storageKey = 'featherflow_auth_session';
  static const _pendingSignupKey = 'featherflow_pending_signup';

  String get baseUrl {
    const fromEnvironment =
        String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (fromEnvironment.isNotEmpty) {
      return fromEnvironment;
    }
    // 10.0.2.2 is an Android-emulator-only alias. Desktop and iOS
    // simulators reach a locally running Django server through loopback.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  Future<AuthSession?> getStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(_storageKey);
    if (payload == null || payload.isEmpty) {
      return null;
    }
    final session = AuthSession.fromJson(jsonDecode(payload));
    _currentSession = session;
    return session;
  }

  Future<void> saveSession(AuthSession session) async {
    _currentSession = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(session.toJson()));
    notifyListeners();
  }

  Future<void> clearSession() async {
    _currentSession = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_pendingSignupKey);
    notifyListeners();
  }

  Future<String> getRoleDestination(String? role) async {
    final normalizedRole = (role ?? '').toLowerCase();
    return {
          'admin': AppRoutes.adminDashboard,
          'doctor': AppRoutes.doctorDashboard,
          'pharmacy': AppRoutes.pharmacyDashboard,
          'delivery': AppRoutes.deliveryDashboard,
          'researcher': AppRoutes.researchDashboard,
        }[normalizedRole] ??
        AppRoutes.farmerDashboard;
  }

  Future<void> savePendingRegistration({
    required String email,
    required String password,
    required String phone,
    required String fullName,
    required String address,
    required String dateOfBirth,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'email': email.trim(),
      'password': password,
      'phone': phone.trim(),
      'full_name': fullName.trim(),
      'address': address.trim(),
      'date_of_birth': dateOfBirth,
    };
    await prefs.setString(_pendingSignupKey, jsonEncode(payload));
  }

  Future<Map<String, dynamic>> getPendingRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(_pendingSignupKey);
    if (payload == null || payload.isEmpty) {
      return {};
    }
    return jsonDecode(payload) as Map<String, dynamic>;
  }

  Future<void> clearPendingRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingSignupKey);
    notifyListeners();
  }

  Future<bool> isAuthenticated() async {
    final session = await getStoredSession();
    return session != null && session.accessToken.isNotEmpty;
  }

  Future<AuthSession> login(
      {required String email, required String password}) async {
    final response = await _post('/api/auth/login/', {
      'email': email.trim(),
      'password': password,
    });

    if (response.statusCode != 200) {
      throw AuthException(_readErrorMessage(response));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final session = AuthSession.fromJson(data);
    await saveSession(session);
    return session;
  }

  Future<AuthSession> register({
    required String email,
    required String password,
    required String phone,
    required String fullName,
    required String role,
    required String address,
    required String dateOfBirth,
    required Map<String, dynamic> roleData,
  }) async {
    final payload = {
      'email': email.trim(),
      'password': password,
      'password2': password,
      'phone': phone.trim(),
      'full_name': fullName.trim(),
      'present_address': address.trim(),
      'date_of_birth': dateOfBirth,
      'consent_terms': true,
      'consent_background_check': true,
      'preferred_language': 'en',
      'role': role.toLowerCase(),
      'role_data': roleData,
    };

    final response = await _post('/api/auth/register/', payload);
    if (response.statusCode != 201) {
      throw AuthException(_readErrorMessage(response));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final session = AuthSession.fromJson(data);
    await saveSession(session);
    return session;
  }

  Future<http.Response> _post(String path, Map<String, dynamic> payload) async {
    final uri = Uri.parse('$baseUrl$path');
    return http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(payload),
    );
  }

  String _readErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('detail')) {
          return decoded['detail'].toString();
        }
        if (decoded.containsKey('non_field_errors')) {
          return decoded['non_field_errors'].toString();
        }
        return decoded.entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join('\n');
      }
    } catch (_) {}
    return 'Request failed (${response.statusCode})';
  }
}
