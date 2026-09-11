import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../router/app_router.dart';
import 'upload_helpers.dart';

class AuthException implements Exception {
  AuthException(this.message,
      {this.fieldErrors = const {},
      this.statusCode,
      this.next = '',
      this.data = const {}});

  final String message;

  /// Field name -> message, so a form can show errors inline.
  final Map<String, String> fieldErrors;
  final int? statusCode;

  /// A `next` hint from the server, e.g. 'verify_email' / 'pending_approval'.
  final String next;

  /// The decoded response body (for `email`, `debug_code`, `retry_after`, …).
  final Map<String, dynamic> data;

  @override
  String toString() => message;
}

/// Outcome of registration or of confirming a verification code.
///
///  * [verificationRequired] — the account exists but an email/phone code must
///    be confirmed before anything else. [email] / [channel] identify it and
///    [debugCode] is the dev-mode auto-fill hint.
///  * [session] set — the account is active and signed in.
///  * [pending] — the account is created and verified but awaits admin review.
class RegistrationResult {
  RegistrationResult({
    this.session,
    this.pending = false,
    this.verificationRequired = false,
    this.message = '',
    this.email = '',
    this.channel = 'email',
    this.debugCode = '',
    this.devDelivery = false,
  });

  final AuthSession? session;
  final bool pending;
  final bool verificationRequired;
  final String message;
  final String email;
  final String channel;
  final String debugCode;

  /// True when the server has no real email/SMS provider — the code is only in
  /// the backend terminal (and auto-filled from [debugCode]).
  final bool devDelivery;
}

/// Result of requesting a verification / reset code.
class CodeRequestResult {
  CodeRequestResult({
    this.detail = '',
    this.resendCooldown = 60,
    this.debugCode = '',
    this.devDelivery = false,
  });

  final String detail;
  final int resendCooldown;
  final String debugCode;
  final bool devDelivery;
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
    this.profilePhotoUrl = '',
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
      profilePhotoUrl: json['profile_photo_url']?.toString() ?? '',
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
  final String profilePhotoUrl;

  AuthUser copyWith({String? profilePhotoUrl}) => AuthUser(
        id: id,
        email: email,
        fullName: fullName,
        roles: roles,
        accountStatus: accountStatus,
        phone: phone,
        presentAddress: presentAddress,
        dateOfBirth: dateOfBirth,
        profileData: profileData,
        profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      );

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

  AuthSession copyWithUser(AuthUser newUser) => AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: newUser,
      );

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
          'profile_photo_url': user.profilePhotoUrl,
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
    // Any admin role (admin, admin_super, admin_finance, …) lands on the panel.
    if (normalizedRole == 'admin' || normalizedRole.startsWith('admin_')) {
      return AppRoutes.adminDashboard;
    }
    return {
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
    String nationalId = '',
    String emergencyContact = '',
    String preferredLanguage = 'en',
    bool consentTerms = false,
    String profilePhotoUrl = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'email': email.trim(),
      'password': password,
      'phone': phone.trim(),
      'full_name': fullName.trim(),
      'address': address.trim(),
      'date_of_birth': dateOfBirth,
      'national_id': nationalId.trim(),
      'emergency_contact': emergencyContact.trim(),
      'preferred_language': preferredLanguage,
      'consent_terms': consentTerms,
      'profile_photo_url': profilePhotoUrl.trim(),
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
      throw _errorFrom(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final session = AuthSession.fromJson(data);
    await saveSession(session);
    return session;
  }

  Future<RegistrationResult> register({
    required String email,
    required String password,
    required String phone,
    required String fullName,
    required String role,
    required String address,
    required String dateOfBirth,
    required Map<String, dynamic> roleData,
    bool consentTerms = true,
    String nationalId = '',
    String emergencyContact = '',
    String preferredLanguage = 'en',
    String profilePhotoUrl = '',
  }) async {
    if (profilePhotoUrl.isNotEmpty) {
      roleData = {...roleData, 'profile_photo_url': profilePhotoUrl};
    }
    final payload = {
      'email': email.trim().toLowerCase(),
      'password': password,
      'password2': password,
      'phone': phone.trim(),
      'full_name': fullName.trim(),
      'present_address': address.trim(),
      'date_of_birth': dateOfBirth,
      'consent_terms': consentTerms,
      'consent_background_check': true,
      'preferred_language': preferredLanguage,
      if (nationalId.trim().isNotEmpty) 'national_id_number': nationalId.trim(),
      if (emergencyContact.trim().isNotEmpty)
        'emergency_contact_name': emergencyContact.trim(),
      'role': role.toLowerCase(),
      'role_data': roleData,
    };

    final response = await _post('/api/auth/register/', payload);
    if (response.statusCode != 201) {
      throw _errorFrom(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _registrationOutcome(data, clearPendingOnTerminal: true);
  }

  /// Interpret a register / verify-confirm response body.
  Future<RegistrationResult> _registrationOutcome(
    Map<String, dynamic> data, {
    bool clearPendingOnTerminal = false,
  }) async {
    final next = data['next']?.toString() ?? '';
    final message = data['detail']?.toString() ?? '';

    if (next == 'verify_email' || next == 'verify_phone') {
      return RegistrationResult(
        verificationRequired: true,
        message: message,
        email: data['email']?.toString() ??
            (data['user'] as Map?)?['email']?.toString() ?? '',
        channel: data['channel']?.toString() ?? 'email',
        debugCode: data['debug_code']?.toString() ?? '',
        devDelivery: data['dev_delivery'] == true,
      );
    }

    if (data['access'] != null && data['access'].toString().isNotEmpty) {
      final session = AuthSession.fromJson(data);
      await saveSession(session);
      if (clearPendingOnTerminal) await clearPendingRegistration();
      return RegistrationResult(session: session, message: message);
    }

    // Verified but awaiting admin review — no session.
    if (clearPendingOnTerminal) await clearPendingRegistration();
    return RegistrationResult(
      pending: true,
      message: message.isEmpty ? 'Your account is pending approval.' : message,
    );
  }

  /// Request (or resend) an email/phone verification code for [email].
  Future<CodeRequestResult> requestVerificationCode({
    required String email,
    String channel = 'email',
  }) async {
    final response = await _post('/api/auth/verify/request/', {
      'email': email.trim().toLowerCase(),
      'channel': channel,
    });
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw _errorFrom(response);
    }
    return CodeRequestResult(
      detail: data['detail']?.toString() ?? '',
      resendCooldown: (data['resend_cooldown'] as num?)?.toInt() ?? 60,
      debugCode: data['debug_code']?.toString() ?? '',
      devDelivery: data['dev_delivery'] == true,
    );
  }

  /// Confirm an email/phone verification code. Returns the resulting session,
  /// pending status, or (if phone is still outstanding) another verification step.
  Future<RegistrationResult> confirmVerificationCode({
    required String email,
    required String code,
    String channel = 'email',
  }) async {
    final response = await _post('/api/auth/verify/confirm/', {
      'email': email.trim().toLowerCase(),
      'channel': channel,
      'code': code.trim(),
    });
    final data = _decode(response);
    if (response.statusCode == 200) {
      return _registrationOutcome(data, clearPendingOnTerminal: true);
    }
    if (response.statusCode == 403 &&
        (data['next'] == 'pending_approval' ||
            data['next'] == 'verify_phone' ||
            data['next'] == 'verify_email')) {
      return _registrationOutcome(data, clearPendingOnTerminal: true);
    }
    throw _errorFrom(response);
  }

  /// Start a self-service password reset. Always succeeds (no account enumeration).
  Future<CodeRequestResult> requestPasswordReset({required String email}) async {
    final response = await _post('/api/auth/password-reset/request/', {
      'email': email.trim().toLowerCase(),
    });
    final data = _decode(response);
    if (response.statusCode != 200) throw _errorFrom(response);
    return CodeRequestResult(
      detail: data['detail']?.toString() ?? '',
      resendCooldown: (data['resend_cooldown'] as num?)?.toInt() ?? 60,
      debugCode: data['debug_code']?.toString() ?? '',
      devDelivery: data['dev_delivery'] == true,
    );
  }

  /// Complete a password reset. On success the old sessions are invalidated
  /// server-side and the user must sign in again.
  Future<String> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await _post('/api/auth/password-reset/confirm/', {
      'email': email.trim().toLowerCase(),
      'code': code.trim(),
      'new_password': newPassword,
    });
    final data = _decode(response);
    if (response.statusCode != 200) throw _errorFrom(response);
    await clearSession();
    return data['detail']?.toString() ?? 'Your password has been updated.';
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Uploads one signup document/photo and returns its stored URL.
  /// [kind] is one of profile_photo, license_photo, council_proof,
  /// trade_license, cv, certificate, vehicle_photo, id_document.
  Future<String> uploadRegistrationDoc({
    required Uint8List bytes,
    required String filename,
    required String kind,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/registration-upload/');
    final request = http.MultipartRequest('POST', uri)
      ..fields['kind'] = kind
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        // Flutter's MultipartFile defaults to application/octet-stream, which
        // the backend used to reject. Derive the real type from the extension.
        contentType: mediaTypeForFilename(filename),
      ));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 201) {
      throw _errorFrom(response);
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['url'].toString();
  }

  /// Replace the signed-in user's profile photo. Multipart upload to the
  /// authenticated endpoint; on success the stored session's
  /// [AuthUser.profilePhotoUrl] is updated in place and listeners are notified,
  /// so avatars bound to the session refresh without an app restart.
  /// Throws [AuthException] with a readable message on failure — the old photo
  /// is left untouched by the server.
  Future<String> updateProfilePhoto(
      {required Uint8List bytes, required String filename}) async {
    final session = currentSession ?? await getStoredSession();
    if (session == null) throw AuthException('Please sign in again.');
    final uri = Uri.parse('$baseUrl/api/auth/profile-photo/');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename, contentType: mediaTypeForFilename(filename)));
    final response =
        await http.Response.fromStream(await request.send());
    if (response.statusCode != 200) throw _errorFrom(response);
    final url = (jsonDecode(response.body) as Map<String, dynamic>)['profile_photo_url']
        .toString();
    await _applyProfilePhoto(session, url);
    return url;
  }

  /// Clear the photo (initials fall back).
  Future<void> clearProfilePhoto() async {
    final session = currentSession ?? await getStoredSession();
    if (session == null) throw AuthException('Please sign in again.');
    final response = await http.delete(
      Uri.parse('$baseUrl/api/auth/profile-photo/'),
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
    if (response.statusCode != 200) throw _errorFrom(response);
    await _applyProfilePhoto(session, '');
  }

  Future<void> _applyProfilePhoto(AuthSession session, String url) async {
    final updated =
        session.copyWithUser(session.user.copyWith(profilePhotoUrl: url));
    _currentSession = updated;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(updated.toJson()));
    } catch (_) {}
    notifyListeners();
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

  AuthException _errorFrom(http.Response response) {
    final fieldErrors = <String, String>{};
    String message = 'Request failed (${response.statusCode}).';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        String flatten(dynamic v) {
          if (v is List) return v.map(flatten).join(' ');
          if (v is Map) {
            return v.entries.map((e) => '${_label(e.key)}: ${flatten(e.value)}').join('  ');
          }
          return v.toString();
        }

        if (decoded.containsKey('detail') && decoded['detail'] is! Map) {
          message = decoded['detail'].toString();
        } else if (decoded.containsKey('non_field_errors')) {
          message = flatten(decoded['non_field_errors']);
        } else {
          final parts = <String>[];
          decoded.forEach((key, value) {
            if (key == 'user' || key == 'next' || key == 'account_status') return;
            if (value is Map) {
              value.forEach((k, v) {
                fieldErrors[k.toString()] = flatten(v);
                parts.add('${_label(k)}: ${flatten(v)}');
              });
            } else {
              fieldErrors[key] = flatten(value);
              parts.add('${_label(key)}: ${flatten(value)}');
            }
          });
          if (parts.isNotEmpty) message = parts.join('\n');
        }
      }
    } catch (_) {}
    if (response.statusCode == 409 && !message.toLowerCase().contains('exist')) {
      message = 'An account with those details already exists.';
    }
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    return AuthException(message,
        fieldErrors: fieldErrors,
        statusCode: response.statusCode,
        next: body['next']?.toString() ?? '',
        data: body);
  }

  static String _label(dynamic key) {
    final s = key.toString().replaceAll('_', ' ');
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }
}
