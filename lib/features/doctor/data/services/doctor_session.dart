import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../../core/chat/chat_core.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/network/user_updates_service.dart';
import '../../../../core/network/realtime_chat_service.dart';
import '../models/doctor_models.dart';
// Placeholder profile only — no demo consultation data is imported.
import 'doctor_api_service.dart';

const _emptyProfile = DoctorProfile(
  id: '',
  name: '',
  specialty: '',
  licenseNo: '',
  phone: '',
  email: '',
  rating: 0,
  totalRatings: 0,
  isVerified: false,
  availability: DoctorAvailability.offline,
);

class DoctorSession extends ChangeNotifier {
  static final DoctorSession instance = DoctorSession._();
  DoctorSession._() {
    // Empty until the signed-in doctor's real profile loads (name from the
    // session in _loadRegisteredProfile, everything else from the API). It
    // used to start from a demo profile (rating 4.7 from 128 ratings,
    // "verified"), which copyWith kept and which stayed on screen whenever
    // the dashboard request failed. See DOCTOR_RATINGS_FIX.md.
    _profile = _emptyProfile;
    // Consultation data starts EMPTY, never as demo rows. These used to be
    // seeded with fake appointments/cases/chats/earnings, and because a failed
    // refresh keeps the previous lists, a doctor whose refresh failed was
    // shown fabricated patients instead of their real queue. See
    // DOCTOR_CONSULTATION_QUEUE_FIX.md.
    _appointments = [];
    _cases = [];
    _chatThreads = [];
    _earnings = [];
    _ratings = [];
    AuthService.instance.addListener(_loadRegisteredProfile);
    // Real-time: reflect admin verification / suspension from /api/me/updates/.
    UserUpdatesService.instance.addListener(_syncFromRealtime);
    _loadRegisteredProfile();
  }

  bool _platformVerified = false;
  bool _accessRevoked = false;

  /// True once an admin has verified this doctor's registration.
  bool get isPlatformVerified => _platformVerified;

  /// True if an admin suspended the account mid-session.
  bool get accessRevoked => _accessRevoked;

  void _syncFromRealtime() {
    final updates = UserUpdatesService.instance;
    final profileVerified = updates.profile['is_verified'] == true;
    final verified = updates.verified || profileVerified;
    var changed = false;
    if (verified != _platformVerified) {
      _platformVerified = verified;
      changed = true;
    }
    if (updates.accessRevoked != _accessRevoked) {
      _accessRevoked = updates.accessRevoked;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  late DoctorProfile _profile;
  Map<String, dynamic> _dashboardSummary = const {};
  late List<DoctorAppointment> _appointments;
  late List<DoctorCase> _cases;
  late List<ChatThread> _chatThreads;
  late List<EarningsRecord> _earnings;
  late List<FarmerRating> _ratings;
  List<Map<String, dynamic>> _notifications = [];
  int _unreadNotifications = 0;
  AuthUser? _registeredUser;
  bool _isLoading = false;
  String? _error;
  final RealtimeChatService _realtime = RealtimeChatService();
  Timer? _notificationTimer;

  AuthUser? get registeredUser => _registeredUser;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> _loadRegisteredProfile() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (session == null) return;
    final user = session.user;
    if (!user.roles.any((role) => role.toLowerCase() == 'doctor')) return;
    _registeredUser = user;
    _profile = _profile.copyWith(
      id: user.id,
      name: user.fullName.isNotEmpty
          ? user.fullName
          : user.email.split('@').first,
      email: user.email,
      phone: user.phone,
      specialty: user.profileValue('specialty'),
      licenseNo: user.profileValue('license_number'),
    );
    notifyListeners();
    await refresh();
    _notificationTimer ??= Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshNotifications(),
    );
  }

  Future<void> _refreshNotifications() async {
    final user = AuthService.instance.currentSession?.user;
    if (user == null ||
        !user.roles.any((role) => role.toLowerCase() == 'doctor')) {
      _notificationTimer?.cancel();
      _notificationTimer = null;
      return;
    }
    try {
      final data = await DoctorApiService.notifications();
      final fresh = (data['notifications'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
      final knownIds = _notifications.map((n) => n['id']).toSet();
      final arrived = _notificationsPrimed &&
          fresh.any((n) => !knownIds.contains(n['id']));
      _notifications = fresh;
      _notificationsPrimed = true;
      _unreadNotifications = (data['unread_count'] as num? ?? 0).toInt();
      notifyListeners();
      // This poll (every 4s) used to refresh ONLY the notification list, so a
      // doctor was told about a new consultation request while the request
      // queue itself never reloaded. A newly arrived notification now pulls
      // the real lists (appointments, cases, chats, earnings) too.
      if (arrived) unawaited(refresh());
    } catch (_) {
      // The next poll retries without interrupting clinical work.
    }
  }

  bool _notificationsPrimed = false;
  bool _refreshQueued = false;
  bool _appointmentsLoaded = false;
  DateTime? _loadingSince;
  int _refreshGeneration = 0;

  /// The one parser for `GET /api/doctor/appointments/` — used by [refresh]
  /// and by tests, so tests exercise the real parse path.
  static List<DoctorAppointment> parseAppointments(Map<String, dynamic> data) =>
      (data['appointments'] as List? ?? const [])
          .map((x) => DoctorAppointment.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList();

  /// Test seam: load a real API payload through [parseAppointments].
  @visibleForTesting
  void debugLoadAppointmentsPayload(Map<String, dynamic> payload) {
    _appointments = parseAppointments(payload);
    _appointmentsLoaded = true;
    notifyListeners();
  }

  /// Test seam: load a real `GET /api/doctor/dashboard/` payload through the
  /// same parsing as [refresh].
  @visibleForTesting
  void debugLoadDashboardPayload(Map<String, dynamic> payload) {
    _profile = DoctorProfile.fromJson(Map<String, dynamic>.from(payload['profile'] as Map));
    _dashboardSummary = Map<String, dynamic>.from(payload['summary'] as Map? ?? const {});
    notifyListeners();
  }

  /// Test seam: load a real `GET /api/doctor/earnings/` payload.
  @visibleForTesting
  void debugLoadEarningsPayload(Map<String, dynamic> payload) {
    List<Map<String, dynamic>> rows(String key) => (payload[key] as List? ?? const [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    _earnings = rows('earnings').map(EarningsRecord.fromJson).toList();
    _ratings = rows('ratings').map(FarmerRating.fromJson).toList();
    notifyListeners();
  }

  /// True once the real appointment list has loaded at least once.
  bool get appointmentsLoaded => _appointmentsLoaded;

  Future<void> refresh() async {
    // A refresh stuck on a hung request must not block every later one (each
    // would only be queued behind it, freezing the queue). Past this age it
    // is treated as abandoned. Timer-free on purpose: no Timer outlives a
    // screen, and the newer run's generation wins the final state.
    final stuck = _loadingSince != null &&
        DateTime.now().difference(_loadingSince!) > const Duration(seconds: 30);
    if (_isLoading && !stuck) {
      // Never drop a refresh: the in-flight one may predate the request that
      // triggered this call (e.g. a just-arrived consultation notification).
      _refreshQueued = true;
      return;
    }
    final generation = ++_refreshGeneration;
    _loadingSince = DateTime.now();
    _isLoading = true;
    _error = null;
    notifyListeners();
    final errors = <String>[];

    // Each section is fetched and parsed on its own. Previously everything
    // shared one try block, so a single unparseable row (an open-ended
    // request's null `scheduled_at`) threw before cases/earnings/chats/
    // notifications were assigned, and the whole session silently kept
    // whatever it had before. A failing section now keeps its own last real
    // data and reports an error, without blocking the others.
    Future<void> section(String name, Future<void> Function() load) async {
      try {
        await load();
      } catch (e) {
        errors.add('$name: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }

    List<Map<String, dynamic>> rows(Map<String, dynamic> data, String key) =>
        (data[key] as List? ?? const [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();

    await Future.wait([
      section('dashboard', () async {
        final d = await DoctorApiService.get('dashboard');
        _profile = DoctorProfile.fromJson(Map<String, dynamic>.from(d['profile'] as Map));
        _dashboardSummary = Map<String, dynamic>.from(d['summary'] as Map? ?? const {});
      }),
      section('appointments', () async {
        final d = await DoctorApiService.get('appointments');
        _appointments = parseAppointments(d);
        _appointmentsLoaded = true;
      }),
      section('cases', () async {
        final d = await DoctorApiService.get('cases');
        _cases = rows(d, 'cases').map(DoctorCase.fromJson).toList();
      }),
      section('earnings', () async {
        final d = await DoctorApiService.get('earnings');
        _earnings = rows(d, 'earnings').map(EarningsRecord.fromJson).toList();
        _ratings = rows(d, 'ratings').map(FarmerRating.fromJson).toList();
      }),
      section('conversations', () async {
        final d = await DoctorApiService.get('conversations');
        final fresh = rows(d, 'conversations').map(ChatThread.fromJson).toList();
        // Server rows win; only messages still sending/failed locally are
        // kept, so a poll neither duplicates nor drops an unsent bubble.
        _chatThreads = [
          for (final t in fresh)
            t.copyWith(
                messages: ChatTimeline.reconcile(
                    t.messages, _chatThreadOf(t.id)?.messages ?? const [])),
        ];
      }),
      section('notifications', () async {
        final d = await DoctorApiService.notifications();
        _notifications = rows(d, 'notifications');
        _notificationsPrimed = true;
        _unreadNotifications = (d['unread_count'] as num? ?? 0).toInt();
      }),
    ]);

    if (generation != _refreshGeneration) return; // superseded by a newer run
    _error = errors.isEmpty ? null : errors.join('\n');
    _isLoading = false;
    _loadingSince = null;
    notifyListeners();
    if (_refreshQueued) {
      _refreshQueued = false;
      unawaited(refresh());
    }
  }

  DoctorProfile get profile => _profile;
  Map<String, dynamic> get dashboardSummary => Map.unmodifiable(_dashboardSummary);
  List<DoctorAppointment> get appointments => List.unmodifiable(_appointments);
  List<DoctorCase> get cases => List.unmodifiable(_cases);
  List<ChatThread> get chatThreads => List.unmodifiable(_chatThreads);
  List<EarningsRecord> get earnings => List.unmodifiable(_earnings);
  List<FarmerRating> get ratings => List.unmodifiable(_ratings);
  List<Map<String, dynamic>> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadNotifications => _unreadNotifications;

  Future<void> markNotificationsRead() async {
    await DoctorApiService.markNotificationsRead();
    _unreadNotifications = 0;
    for (final item in _notifications) {
      item['is_read'] = true;
    }
    notifyListeners();
  }

  // ── Computed stats ──────────────────────────────────────────────────────────

  int get totalClients => _appointments.map((a) => a.farmerName).toSet().length;

  /// Booked for today. An open-ended request has no slot yet, so it isn't a
  /// "today" appointment — it is counted by [pendingRequestCount] instead.
  List<DoctorAppointment> get todayAppointments {
    final now = DateTime.now();
    return _appointments.where((a) {
      final at = a.scheduledAt;
      return at != null && at.year == now.year && at.month == now.month && at.day == now.day;
    }).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  }

  int get todayAppointmentCount => todayAppointments.length;

  /// The request queue: every consultation still awaiting this doctor's
  /// decision (backend `requested`), with or without a preferred slot.
  List<DoctorAppointment> get pendingRequests =>
      _appointments.where((a) => a.status == AppointmentStatus.pending).toList()
        ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

  /// Counted from the same list the queue renders, so the dashboard and the
  /// queue can never disagree. Before the list first loads, falls back to the
  /// server's authoritative `summary.pending_requests`.
  int get pendingRequestCount => _appointmentsLoaded
      ? pendingRequests.length
      : (_dashboardSummary['pending_requests'] as num? ?? 0).toInt();

  /// Accepted consultations whose case work isn't finished: open, or closed
  /// and awaiting "Mark as Complete".
  int get activeCases => _cases
      .where((c) => c.stage == CaseStage.open || c.stage == CaseStage.closed)
      .length;

  /// Consultations marked complete. A closed case is still awaiting
  /// "Mark as Complete" on its Case page, so it is not counted.
  int get completedCases => _cases
      .where((c) =>
          c.stage == CaseStage.completed || c.stage == CaseStage.prescribed)
      .length;

  int get urgentRequests => _appointments
      .where((a) => a.isUrgent && a.status == AppointmentStatus.pending)
      .length;

  int get unreadMessages =>
      _chatThreads.fold(0, (sum, t) => sum + t.unreadCount);

  int get pendingFollowUpCount =>
      _cases.where((c) => c.status == CaseStatus.followUp).length;

  List<DoctorCase> get pendingFollowUps =>
      _cases.where((c) => c.status == CaseStatus.followUp).toList();

  double get totalEarned => _earnings
      .where((e) => e.paymentReceived)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get totalGrossReceived => _earnings
      .where((e) => e.paymentReceived)
      .fold(0.0, (sum, e) => sum + e.grossAmount);

  double get thisMonthEarned {
    final now = DateTime.now();
    return _earnings
        .where((e) =>
            e.paymentReceived &&
            e.date.year == now.year &&
            e.date.month == now.month)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get pendingAmount => _earnings
      .where((e) => !e.isPaid && e.amount > 0)
      .fold(0.0, (sum, e) => sum + e.amount);

  // ── Actions ─────────────────────────────────────────────────────────────────

  void setAvailability(DoctorAvailability availability) async {
    _profile = _profile.copyWith(availability: availability);
    notifyListeners();
    try {
      await DoctorApiService.patch(
          'profile', {'availability': availability.name});
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Returns null on success, or the server's refusal message (which the
  /// screen shows) — the optimistic change is reverted in that case.
  Future<String?> updateAppointmentStatus(String id, AppointmentStatus status) async {
    final idx = _appointments.indexWhere((a) => a.id == id);
    if (idx < 0) return 'This consultation is no longer available.';
    final previous = _appointments[idx];
    final action = {
      AppointmentStatus.accepted: 'accept',
      AppointmentStatus.inProgress: 'start',
      AppointmentStatus.rejected: 'reject',
      AppointmentStatus.completed: 'complete',
      AppointmentStatus.noShow: 'no_show',
      AppointmentStatus.rescheduled: 'reschedule'
    }[status];
    if (action == null || status == AppointmentStatus.rescheduled) return null;
    _appointments[idx] = previous.copyWith(status: status);
    notifyListeners();
    try {
      await DoctorApiService.post(
          'appointments/$id/action', {'action': action});
      await refresh();
      return null;
    } catch (e) {
      // Undo the optimistic change — it used to stay on screen ("Accepted")
      // even when the server refused the transition — then resync.
      final i = _appointments.indexWhere((a) => a.id == id);
      if (i >= 0) _appointments[i] = previous;
      final message = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      unawaited(refresh());
      return message;
    }
  }

  Future<void> rejectAppointment(String id, String reason) async {
    try {
      await DoctorApiService.post(
          'appointments/$id/action', {'action': 'reject', 'reason': reason});
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> rescheduleAppointment(String id, DateTime scheduledAt) async {
    try {
      final day =
          '${scheduledAt.year}-${scheduledAt.month.toString().padLeft(2, '0')}-${scheduledAt.day.toString().padLeft(2, '0')}';
      final clock =
          '${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}';
      await DoctorApiService.post('appointments/$id/action', {
        'action': 'reschedule',
        'appointment_date': day,
        'appointment_time': clock,
      });
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ── Case page workflow (DOCTOR_CASE_PAGE_FIX.md) ─────────────────────────
  // Every call awaits the server and swaps the server's updated case into
  // [cases]; the server decides what the case's stage allows. (The old
  // fire-and-forget `updateCaseStatus` re-sent the whole case — blanking any
  // field the page didn't hold — and swallowed refusals.)

  final Set<String> _caseBusy = {};

  /// True while a save / close / complete / prescription for [caseId] is in
  /// flight — the Case page disables its actions meanwhile.
  bool isCaseBusy(String caseId) => _caseBusy.contains(caseId);

  void _putCase(DoctorCase fresh) {
    final idx = _cases.indexWhere((c) => c.id == fresh.id);
    if (idx >= 0) {
      _cases[idx] = fresh;
    } else {
      _cases.insert(0, fresh);
    }
    notifyListeners();
  }

  Future<DoctorCase> _caseCall(
      String caseId, Future<Map<String, dynamic>> Function() call,
      {bool refreshAfter = false}) async {
    if (!_caseBusy.add(caseId)) {
      throw AuthException('This case is already being saved — please wait.');
    }
    notifyListeners();
    try {
      final fresh = DoctorCase.fromJson(await call());
      _putCase(fresh);
      // Schedule, dashboard counters and follow-ups depend on the change.
      if (refreshAfter) unawaited(refresh());
      return fresh;
    } finally {
      _caseBusy.remove(caseId);
      notifyListeners();
    }
  }

  /// Reloads one case (Case page open / pull-to-refresh / deep link).
  Future<DoctorCase> loadCase(String caseId) async {
    final fresh = DoctorCase.fromJson(await DoctorApiService.get('cases/$caseId'));
    _putCase(fresh);
    return fresh;
  }

  /// Saves only [fields] (API names → values); optionally moves the case to
  /// [status] in the same request. Throws [AuthException] with the server's
  /// reason and per-field errors.
  Future<DoctorCase> saveCaseFields(String caseId, Map<String, dynamic> fields,
          {CaseStatus? status}) =>
      _caseCall(
          caseId,
          () => DoctorApiService.patch('cases/$caseId', {
                ...fields,
                if (status != null) 'status': _apiCaseStatus(status),
              }),
          refreshAfter: status != null);

  /// Close case (saving any pending edits with it). The server requires a
  /// diagnosis and treatment plan.
  Future<DoctorCase> closeCase(String caseId,
          [Map<String, dynamic> pendingFields = const {}]) =>
      saveCaseFields(caseId, pendingFields, status: CaseStatus.closed);

  Future<DoctorCase> reopenCase(String caseId) =>
      saveCaseFields(caseId, const {}, status: CaseStatus.open);

  /// "Mark as Complete" on the Case page: completes the consultation through
  /// the existing action endpoint (receipt, notification, history; idempotent
  /// on repeat) and returns the reloaded case.
  Future<DoctorCase> completeCase(String caseId) {
    final appointmentId = findCase(caseId)?.appointmentId;
    return _caseCall(caseId, () async {
      final id = appointmentId ??
          '${(await DoctorApiService.get('cases/$caseId'))['appointment_id']}';
      await DoctorApiService.post('appointments/$id/action', {'action': 'complete'});
      return DoctorApiService.get('cases/$caseId');
    }, refreshAfter: true);
  }

  /// "Issue prescription & advice" on the Case page (consultation must be
  /// completed — the server refuses otherwise).
  Future<DoctorCase> issueCasePrescription(
    String caseId, {
    required List<MedicineSuggestion> medicines,
    required String caseAdvice,
    String dosageNotes = '',
    String followUpInstructions = '',
    String referredTo = '',
    DateTime? followUpAt,
  }) {
    final appointmentId = findCase(caseId)?.appointmentId;
    return _caseCall(caseId, () async {
      String two(int v) => v.toString().padLeft(2, '0');
      await DoctorApiService.post('prescriptions', {
        'consultation_id': appointmentId,
        'medicines': [
          for (final m in medicines)
            {
              'name': m.name,
              'dosage': m.dosage,
              'duration': m.duration,
              'notes': m.notes ?? ''
            }
        ],
        'case_advice': caseAdvice,
        if (dosageNotes.isNotEmpty) 'dosage_notes': dosageNotes,
        'follow_up_instructions': followUpInstructions,
        if (referredTo.isNotEmpty) 'referred_to': referredTo,
        if (followUpAt != null) ...{
          'follow_up_date':
              '${followUpAt.year}-${two(followUpAt.month)}-${two(followUpAt.day)}',
          'follow_up_time': '${two(followUpAt.hour)}:${two(followUpAt.minute)}',
        },
      });
      return DoctorApiService.get('cases/$caseId');
    }, refreshAfter: true);
  }

  /// Retries a failed prescription email (same prescription, same stored
  /// PDF — never a new prescription). Returns the reloaded case.
  Future<DoctorCase> retryPrescriptionEmail(String caseId, String prescriptionId) =>
      _caseCall(caseId, () async {
        await DoctorApiService.post('prescriptions/$prescriptionId/resend-email', {});
        return DoctorApiService.get('cases/$caseId');
      });

  static String _apiCaseStatus(CaseStatus status) => switch (status) {
        CaseStatus.inProgress => 'in_progress',
        CaseStatus.followUp => 'follow_up',
        _ => status.name,
      };

  /// Test seam: load a real `GET /api/doctor/cases/` payload.
  @visibleForTesting
  void debugLoadCasesPayload(Map<String, dynamic> payload) {
    _cases = (payload['cases'] as List? ?? const [])
        .map((x) => DoctorCase.fromJson(Map<String, dynamic>.from(x as Map)))
        .toList();
    notifyListeners();
  }

  void setFollowUpDate(String caseId, DateTime date) async {
    final idx = _cases.indexWhere((c) => c.id == caseId);
    if (idx < 0) return;
    _cases[idx] = _cases[idx].copyWith(
      status: CaseStatus.followUp,
      followUpDate: date,
    );
    notifyListeners();
    try {
      await DoctorApiService.post('follow-ups', {
        'consultation_id': _cases[idx].appointmentId,
        'scheduled_date': date.toIso8601String().split('T').first,
        'scheduled_time':
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
      });
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // ── Chat ──────────────────────────────────────────────────────────────────
  // Every list change goes through ChatTimeline, keyed by server id AND the
  // client_message_id the server echoes back, so the optimistic bubble, the
  // REST response, the Socket.IO echo and the next poll can arrive in any
  // order and still render one bubble. See CHAT_MESSAGE_STATE_FIX.md.

  final Set<String> _chatInFlight = {};

  /// True while any message in [threadId] is waiting for the server — the
  /// chat screen disables Send meanwhile (no double submits).
  bool isSendingIn(String threadId) =>
      _chatThreadOf(threadId)?.messages.any((m) =>
          m.status == ChatSendStatus.sending &&
          _chatInFlight.contains(m.clientMessageId)) ??
      false;

  ChatThread? _chatThreadOf(String threadId) {
    for (final t in _chatThreads) {
      if (t.id == threadId) return t;
    }
    return null;
  }

  void _updateThread(String threadId,
      List<ChatMessage> Function(List<ChatMessage> messages) change) {
    final i = _chatThreads.indexWhere((t) => t.id == threadId);
    if (i < 0) return;
    final messages = change(_chatThreads[i].messages);
    final sent = messages.where((m) => m.status == ChatSendStatus.sent);
    final last = sent.isNotEmpty ? sent.last : (messages.isEmpty ? null : messages.last);
    _chatThreads[i] = _chatThreads[i].copyWith(
      messages: messages,
      lastMessage: last?.content,
      lastMessageAt: last?.sentAt,
    );
    notifyListeners();
  }

  String? get _myUserId =>
      AuthService.instance.currentSession?.user.id ?? _registeredUser?.id;

  /// Sends [content] as a new message. Returns the error shown to the user,
  /// or null on success. The bubble stays (marked failed) on error.
  Future<String?> sendMessage(String threadId, String content) {
    final text = content.trim();
    if (text.isEmpty || _chatThreadOf(threadId) == null) {
      return Future.value(null);
    }
    final pending = ChatMessage.pending(text, clientMessageId: newClientMessageId());
    _updateThread(threadId, (list) => ChatTimeline.upsert(list, pending));
    return _deliver(threadId, pending);
  }

  /// Re-sends a failed message with the SAME client_message_id, so a send
  /// that actually reached the server is returned, not duplicated.
  Future<String?> retryMessage(String threadId, String clientMessageId) {
    final failed = _chatThreadOf(threadId)?.messages.where((m) =>
        m.clientMessageId == clientMessageId && m.status == ChatSendStatus.failed);
    if (failed == null || failed.isEmpty) return Future.value(null);
    final again = failed.first.withStatus(ChatSendStatus.sending);
    _updateThread(threadId, (list) => ChatTimeline.upsert(list, again));
    return _deliver(threadId, again);
  }

  Future<String?> _deliver(String threadId, ChatMessage pending) async {
    final clientId = pending.clientMessageId!;
    if (!_chatInFlight.add(clientId)) return null; // already being sent
    notifyListeners();
    try {
      final res = await DoctorApiService.post('conversations/$threadId', {
        'content': pending.content,
        'message_type': pending.type.name,
        'client_message_id': clientId,
      });
      final confirmed = ChatMessage.fromJson(res, myUserId: _myUserId);
      // Replaces the optimistic bubble (and any echo that beat the response).
      _updateThread(threadId,
          (list) => ChatTimeline.upsert(list, confirmed, replacingClientId: clientId));
      return null;
    } catch (e) {
      _updateThread(threadId, (list) => list
          .map((m) => m.clientMessageId == clientId && m.status != ChatSendStatus.sent
              ? m.withStatus(ChatSendStatus.failed)
              : m)
          .toList());
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      _chatInFlight.remove(clientId);
      notifyListeners();
    }
  }

  void markThreadRead(String threadId) async {
    final idx = _chatThreads.indexWhere((t) => t.id == threadId);
    if (idx < 0) return;
    _chatThreads[idx] = _chatThreads[idx].copyWith(unreadCount: 0);
    notifyListeners();
    try {
      await DoctorApiService.patch('conversations/$threadId', {});
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> connectConversation(String threadId) async {
    _realtime.onError = (value) {
      _error = value;
      notifyListeners();
    };
    _realtime.onMessage = (json) => _onRealtimeMessage(threadId, json);
    await _realtime.connect(threadId);
    _realtime.markRead(threadId);
  }

  void _onRealtimeMessage(String threadId, Map<String, dynamic> json) {
    if (json['conversation_id'] != threadId) return;
    final incoming = ChatMessage.fromJson(json, myUserId: _myUserId);
    // Upsert, never append: this may be the echo of our own send arriving
    // before its REST response (matched by client_message_id).
    _updateThread(threadId, (list) => ChatTimeline.upsert(list, incoming));
  }

  /// Test seam: deliver a Socket.IO `message_created` payload through the
  /// real handler, without a live socket.
  @visibleForTesting
  void debugReceiveRealtime(String threadId, Map<String, dynamic> json) =>
      _onRealtimeMessage(threadId, json);

  /// Test seam: load a real `GET /api/doctor/conversations/` payload.
  @visibleForTesting
  void debugLoadConversationsPayload(Map<String, dynamic> payload) {
    _chatThreads = (payload['conversations'] as List? ?? const [])
        .map((x) => ChatThread.fromJson(Map<String, dynamic>.from(x as Map)))
        .toList();
    notifyListeners();
  }

  void disconnectConversation() {
    _realtime.disconnect();
  }

  DoctorCase? findCase(String id) {
    try {
      return _cases.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  List<DoctorCase> searchCases(String query) {
    final q = query.toLowerCase();
    return _cases
        .where((c) =>
            c.farmName.toLowerCase().contains(q) ||
            c.farmerName.toLowerCase().contains(q) ||
            c.breed.toLowerCase().contains(q) ||
            c.diseaseTags.any((t) => t.toLowerCase().contains(q)) ||
            (c.diagnosis?.toLowerCase().contains(q) ?? false))
        .toList();
  }
}
