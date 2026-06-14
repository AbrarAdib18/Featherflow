import 'package:flutter/foundation.dart';
import '../models/doctor_models.dart';
import '../doctor_demo_data.dart';

class DoctorSession extends ChangeNotifier {
  static final DoctorSession instance = DoctorSession._();
  DoctorSession._() {
    _profile = doctorProfile;
    _appointments = List.from(demoAppointments);
    _cases = List.from(demoCases);
    _chatThreads = List.from(demoChatThreads);
    _earnings = List.from(demoEarnings);
    _ratings = List.from(demoRatings);
  }

  late DoctorProfile _profile;
  late List<DoctorAppointment> _appointments;
  late List<DoctorCase> _cases;
  late List<ChatThread> _chatThreads;
  late List<EarningsRecord> _earnings;
  late List<FarmerRating> _ratings;

  DoctorProfile get profile => _profile;
  List<DoctorAppointment> get appointments => List.unmodifiable(_appointments);
  List<DoctorCase> get cases => List.unmodifiable(_cases);
  List<ChatThread> get chatThreads => List.unmodifiable(_chatThreads);
  List<EarningsRecord> get earnings => List.unmodifiable(_earnings);
  List<FarmerRating> get ratings => List.unmodifiable(_ratings);

  // ── Computed stats ──────────────────────────────────────────────────────────

  int get totalClients =>
      _appointments.map((a) => a.farmerName).toSet().length;

  List<DoctorAppointment> get todayAppointments {
    final now = DateTime.now();
    return _appointments
        .where((a) =>
            a.scheduledAt.year == now.year &&
            a.scheduledAt.month == now.month &&
            a.scheduledAt.day == now.day)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  int get todayAppointmentCount => todayAppointments.length;

  int get activeCases => _cases
      .where((c) =>
          c.status == CaseStatus.open || c.status == CaseStatus.inProgress)
      .length;

  int get completedCases =>
      _cases.where((c) => c.status == CaseStatus.closed).length;

  int get urgentRequests => _appointments
      .where((a) =>
          a.isUrgent && a.status == AppointmentStatus.pending)
      .length;

  int get unreadMessages =>
      _chatThreads.fold(0, (sum, t) => sum + t.unreadCount);

  int get pendingFollowUpCount =>
      _cases.where((c) => c.status == CaseStatus.followUp).length;

  List<DoctorCase> get pendingFollowUps =>
      _cases.where((c) => c.status == CaseStatus.followUp).toList();

  double get totalEarned =>
      _earnings.where((e) => e.isPaid).fold(0.0, (sum, e) => sum + e.amount);

  double get thisMonthEarned {
    final now = DateTime.now();
    return _earnings
        .where((e) =>
            e.isPaid &&
            e.date.year == now.year &&
            e.date.month == now.month)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get pendingAmount =>
      _earnings.where((e) => !e.isPaid && e.amount > 0).fold(0.0, (sum, e) => sum + e.amount);

  // ── Actions ─────────────────────────────────────────────────────────────────

  void setAvailability(DoctorAvailability availability) {
    _profile = _profile.copyWith(availability: availability);
    notifyListeners();
  }

  void updateAppointmentStatus(String id, AppointmentStatus status) {
    final idx = _appointments.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    _appointments[idx] = _appointments[idx].copyWith(status: status);
    notifyListeners();
  }

  void updateCaseStatus(String id, CaseStatus status) {
    final idx = _cases.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    _cases[idx] = _cases[idx].copyWith(status: status);
    notifyListeners();
  }

  void setFollowUpDate(String caseId, DateTime date) {
    final idx = _cases.indexWhere((c) => c.id == caseId);
    if (idx < 0) return;
    _cases[idx] = _cases[idx].copyWith(
      status: CaseStatus.followUp,
      followUpDate: date,
    );
    notifyListeners();
  }

  void updateCase(DoctorCase updated) {
    final idx = _cases.indexWhere((c) => c.id == updated.id);
    if (idx >= 0) {
      _cases[idx] = updated;
    } else {
      _cases.insert(0, updated);
    }
    notifyListeners();
  }

  void addPrescription(String caseId, DoctorPrescription prescription) {
    final idx = _cases.indexWhere((c) => c.id == caseId);
    if (idx < 0) return;
    _cases[idx] = _cases[idx].copyWith(prescription: prescription);
    notifyListeners();
  }

  void sendMessage(String threadId, ChatMessage message) {
    final idx = _chatThreads.indexWhere((t) => t.id == threadId);
    if (idx < 0) return;
    _chatThreads[idx] = _chatThreads[idx].copyWith(
      messages: [..._chatThreads[idx].messages, message],
      lastMessage: message.content,
      lastMessageAt: message.sentAt,
    );
    notifyListeners();
  }

  void markThreadRead(String threadId) {
    final idx = _chatThreads.indexWhere((t) => t.id == threadId);
    if (idx < 0) return;
    _chatThreads[idx] = _chatThreads[idx].copyWith(unreadCount: 0);
    notifyListeners();
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
