import '../../../../core/chat/chat_core.dart';

/// How a consultation is delivered. This is independent of the doctor's
/// current availability/presence status.
enum AppointmentMode { online, inPerson }

/// Mirrors the backend's consultation statuses (`requested` arrives as
/// `pending` on the doctor API). `inProgress` and `cancelled` used to be
/// missing, so both silently fell through to `pending` and landed in the
/// request queue. See DOCTOR_CONSULTATION_QUEUE_FIX.md.
enum AppointmentStatus {
  pending,
  accepted,
  inProgress,
  rejected,
  rescheduled,
  completed,
  cancelled,
  noShow
}

enum DoctorAvailability { available, busy, offline }

enum CaseUrgency { routine, moderate, urgent, emergency }

/// Status flows: open → inProgress → followUp → closed
enum CaseStatus { open, inProgress, followUp, closed }

/// Where a case is in the Case page workflow. Computed by the server
/// (doctor/case_workflow.py `case_stage`), which also enforces it:
///
/// awaitingAcceptance → open (edit fields, Close case) → closed (Mark as
/// Complete, or Reopen) → completed (Issue prescription & advice) →
/// prescribed. [ended] = rejected / cancelled / no-show (read-only).
enum CaseStage { awaitingAcceptance, open, closed, completed, prescribed, ended }

/// Which Schedule page section an appointment belongs to; null = not a
/// schedule item (completed / rejected / cancelled / no-show are case
/// history). Mirrors SCHEDULE_*_STATUSES in backend doctor/views.py.
enum ScheduleSection { requests, upcoming }

enum MessageType { text, image, file }

// ── Profile ────────────────────────────────────────────────────────────────────

class DoctorProfile {
  final String id;
  final String name;
  final String specialty;
  final String licenseNo;
  final String phone;
  final String email;
  final double rating;
  final int totalRatings;
  final bool isVerified;
  final DoctorAvailability availability;

  const DoctorProfile({
    required this.id,
    required this.name,
    required this.specialty,
    required this.licenseNo,
    required this.phone,
    required this.email,
    required this.rating,
    required this.totalRatings,
    required this.isVerified,
    required this.availability,
  });

  factory DoctorProfile.fromJson(Map<String, dynamic> j) => DoctorProfile(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        specialty: '${j['specialty'] ?? ''}',
        licenseNo: '${j['license_no'] ?? ''}',
        phone: '${j['phone'] ?? ''}',
        email: '${j['email'] ?? ''}',
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        totalRatings: (j['total_ratings'] as num?)?.toInt() ?? 0,
        isVerified: j['is_verified'] == true,
        availability: _availability('${j['availability'] ?? 'offline'}'),
      );

  DoctorProfile copyWith(
          {String? id,
          String? name,
          String? specialty,
          String? licenseNo,
          String? phone,
          String? email,
          DoctorAvailability? availability}) =>
      DoctorProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        specialty: specialty ?? this.specialty,
        licenseNo: licenseNo ?? this.licenseNo,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        rating: rating,
        totalRatings: totalRatings,
        isVerified: isVerified,
        availability: availability ?? this.availability,
      );

  /// The rating text to show beside the doctor's name (rounded to one
  /// decimal place), or `null` when there are no ratings yet — callers hide
  /// the rating entirely in that case rather than showing a misleading 0.0.
  /// See DOCTOR_DASHBOARD_PROFILE_AND_RATING.md.
  String? get ratingLabel =>
      totalRatings > 0 ? rating.toStringAsFixed(1) : null;
}

// ── Appointment ────────────────────────────────────────────────────────────────

class DoctorAppointment {
  final String id;
  final String farmerName;
  final String farmName;
  final String farmerPhone;

  /// Null for an open-ended request: the farmer chose "any available time"
  /// and the doctor proposes a slot when accepting. The backend has always
  /// sent `scheduled_at: null` for these (doctor/views.py:_appointment_row);
  /// this used to be `DateTime.parse('null')`, which threw and aborted the
  /// doctor's whole data refresh — the reason such requests never appeared.
  final DateTime? scheduledAt;

  /// False for an open-ended request (no slot chosen yet).
  bool get hasSlot => scheduledAt != null;

  /// When the farmer submitted the request (UTC). Present on every row.
  final DateTime? requestedAt;
  final AppointmentMode mode;
  final AppointmentStatus status;
  final bool isUrgent;
  final String urgency;
  final String? caseId;
  final double fee;
  final String? notes;

  const DoctorAppointment({
    required this.id,
    required this.farmerName,
    required this.farmName,
    required this.farmerPhone,
    required this.scheduledAt,
    this.requestedAt,
    required this.mode,
    required this.status,
    required this.isUrgent,
    this.urgency = 'routine',
    this.caseId,
    required this.fee,
    this.notes,
  });

  bool get hasPreferredSlot => scheduledAt != null;

  ScheduleSection? get scheduleSection => switch (status) {
        AppointmentStatus.pending ||
        AppointmentStatus.rescheduled =>
          ScheduleSection.requests,
        AppointmentStatus.accepted ||
        AppointmentStatus.inProgress =>
          ScheduleSection.upcoming,
        _ => null,
      };

  /// Sort key: the booked slot, else when it was requested (open-ended
  /// requests sort by arrival rather than vanishing to the end).
  DateTime get sortKey =>
      scheduledAt ?? requestedAt?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory DoctorAppointment.fromJson(Map<String, dynamic> j) =>
      DoctorAppointment(
        id: '${j['id']}',
        farmerName: '${j['farmer_name'] ?? ''}',
        farmName: '${j['farm_name'] ?? ''}',
        farmerPhone: '${j['farmer_phone'] ?? ''}',
        // Slot times are the clinic's local wall-clock date + time.
        scheduledAt: j['scheduled_at'] == null
            ? null
            : DateTime.tryParse('${j['scheduled_at']}'),
        requestedAt: j['requested_at'] == null
            ? null
            : DateTime.tryParse('${j['requested_at']}')?.toUtc(),
        mode: _appointmentMode('${j['mode']}'),
        status: _appointmentStatus('${j['status']}'),
        isUrgent: j['is_urgent'] == true,
        urgency: '${j['urgency'] ?? 'routine'}',
        caseId: j['case_id']?.toString(),
        fee: (j['fee'] as num?)?.toDouble() ?? 0,
        notes: j['notes']?.toString(),
      );

  DoctorAppointment copyWith({AppointmentStatus? status}) => DoctorAppointment(
        id: id,
        farmerName: farmerName,
        farmName: farmName,
        farmerPhone: farmerPhone,
        scheduledAt: scheduledAt,
        requestedAt: requestedAt,
        mode: mode,
        status: status ?? this.status,
        isUrgent: isUrgent,
        urgency: urgency,
        caseId: caseId,
        fee: fee,
        notes: notes,
      );
}

// ── Prescription ───────────────────────────────────────────────────────────────

class MedicineSuggestion {
  final String name;
  final String dosage;
  final String duration;
  final String? notes;

  const MedicineSuggestion({
    required this.name,
    required this.dosage,
    required this.duration,
    this.notes,
  });

  factory MedicineSuggestion.fromJson(Map<String, dynamic> j) =>
      MedicineSuggestion(
          name: '${j['name'] ?? ''}',
          dosage: '${j['dosage'] ?? ''}',
          duration: '${j['duration'] ?? ''}',
          notes: j['notes']?.toString());
}

class DoctorPrescription {
  final String id;
  final String caseId;
  final List<MedicineSuggestion> medicines;
  final String? dosageNotes;
  final String? caseAdvice;
  final String? followUpInstructions;
  final String? referredTo;
  final DateTime createdAt;

  /// Stable reference printed on the PDF (RX-YYYYMMDD-XXXXXXXX).
  final String? referenceNumber;

  /// Email delivery of the PDF: pending | sending | sent | failed.
  final String emailStatus;
  final String? emailRecipient;
  final String? emailError;
  final bool pdfAvailable;

  const DoctorPrescription({
    required this.id,
    required this.caseId,
    required this.medicines,
    this.dosageNotes,
    this.caseAdvice,
    this.followUpInstructions,
    this.referredTo,
    required this.createdAt,
    this.referenceNumber,
    this.emailStatus = 'pending',
    this.emailRecipient,
    this.emailError,
    this.pdfAvailable = false,
  });

  bool get emailFailed => emailStatus == 'failed';

  factory DoctorPrescription.fromJson(
          Map<String, dynamic> j) =>
      DoctorPrescription(
          id: '${j['id']}',
          caseId: '${j['case_id']}',
          medicines: (j['medicines'] as List? ?? [])
              .map((x) => MedicineSuggestion.fromJson(
                  Map<String, dynamic>.from(x as Map)))
              .toList(),
          dosageNotes: j['dosage_notes']?.toString(),
          caseAdvice: j['case_advice']?.toString(),
          followUpInstructions: j['follow_up_instructions']?.toString(),
          referredTo: j['referred_to']?.toString(),
          // Server time (UTC) in the viewer's local zone.
          createdAt: ChatTime.parseServer(j['issued_at'] ?? j['created_at']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          referenceNumber: j['reference_number']?.toString(),
          emailStatus: '${j['email_status'] ?? (j['email_sent_at'] != null ? 'sent' : 'pending')}',
          emailRecipient: j['email_recipient']?.toString(),
          emailError: j['email_error']?.toString(),
          pdfAvailable: j['pdf_available'] == true);
}

// ── Case ───────────────────────────────────────────────────────────────────────

class DoctorCase {
  final String id;
  final String appointmentId;
  final String farmerName;
  final String farmName;
  final int flockSize;
  final int birdAgeWeeks;
  final String breed;
  final int mortalityCount;
  final List<String> symptoms;
  final String? diagnosis;
  final String? treatmentPlan;
  final List<String> diseaseTags;
  final CaseUrgency urgency;
  final CaseStatus status;
  final String? feedNotes;
  final String? vaccineHistory;
  final String? biosecurityNotes;
  final String? warnings;
  final String? nextSteps;
  final DateTime createdAt;
  final DateTime? followUpDate;
  final DoctorPrescription? prescription;

  /// Case page workflow position — see [CaseStage]. Server-computed.
  final CaseStage stage;

  /// True only while the server will accept clinical field edits.
  final bool editable;

  /// The underlying consultation status (`accepted`, `completed`, …).
  final String consultationStatus;
  final AppointmentMode mode;
  final DateTime? scheduledAt;
  final DateTime? updatedAt;
  final int prescriptionCount;

  const DoctorCase({
    required this.id,
    required this.appointmentId,
    required this.farmerName,
    required this.farmName,
    required this.flockSize,
    required this.birdAgeWeeks,
    required this.breed,
    required this.mortalityCount,
    required this.symptoms,
    this.diagnosis,
    this.treatmentPlan,
    required this.diseaseTags,
    required this.urgency,
    required this.status,
    this.feedNotes,
    this.vaccineHistory,
    this.biosecurityNotes,
    this.warnings,
    this.nextSteps,
    required this.createdAt,
    this.followUpDate,
    this.prescription,
    this.stage = CaseStage.open,
    this.editable = true,
    this.consultationStatus = 'accepted',
    this.mode = AppointmentMode.online,
    this.scheduledAt,
    this.updatedAt,
    this.prescriptionCount = 0,
  });

  /// Saved value of an editable text field, keyed by its API name.
  String fieldValue(String key) => switch (key) {
        'diagnosis' => diagnosis,
        'treatment_plan' => treatmentPlan,
        'warnings' => warnings,
        'next_steps' => nextSteps,
        'feed_notes' => feedNotes,
        'vaccine_history' => vaccineHistory,
        'biosecurity_notes' => biosecurityNotes,
        'disease_tags' => diseaseTags.join(', '),
        _ => null,
      } ??
      '';

  factory DoctorCase.fromJson(Map<String, dynamic> j) {
    final status = _caseStatus('${j['status']}');
    // An older server sends no `stage`: fall back to the case status alone.
    final stage = j['stage'] == null
        ? (status == CaseStatus.closed ? CaseStage.closed : CaseStage.open)
        : _caseStage('${j['stage']}');
    return DoctorCase(
      id: '${j['id']}',
      appointmentId: '${j['appointment_id']}',
      farmerName: '${j['farmer_name'] ?? ''}',
      farmName: '${j['farm_name'] ?? ''}',
      flockSize: (j['flock_size'] as num?)?.toInt() ?? 0,
      birdAgeWeeks: (j['bird_age_weeks'] as num?)?.toInt() ?? 0,
      breed: '${j['breed'] ?? ''}',
      mortalityCount: (j['mortality_count'] as num?)?.toInt() ?? 0,
      symptoms: List<String>.from(j['symptoms'] as List? ?? []),
      diagnosis: j['diagnosis']?.toString(),
      treatmentPlan: j['treatment_plan']?.toString(),
      diseaseTags: List<String>.from(j['disease_tags'] as List? ?? []),
      urgency: _caseUrgency('${j['urgency']}'),
      status: status,
      feedNotes: j['feed_notes']?.toString(),
      vaccineHistory: j['vaccine_history']?.toString(),
      biosecurityNotes: j['biosecurity_notes']?.toString(),
      warnings: j['warnings']?.toString(),
      nextSteps: j['next_steps']?.toString(),
      createdAt: DateTime.parse('${j['created_at']}'),
      followUpDate: j['follow_up_date'] == null
          ? null
          : DateTime.parse('${j['follow_up_date']}'),
      prescription: j['prescription'] is Map
          ? DoctorPrescription.fromJson(
              Map<String, dynamic>.from(j['prescription'] as Map))
          : null,
      stage: stage,
      editable: j['editable'] is bool ? j['editable'] as bool : stage == CaseStage.open,
      consultationStatus: '${j['consultation_status'] ?? ''}',
      mode: _appointmentMode('${j['mode'] ?? 'online'}'),
      scheduledAt: j['scheduled_at'] == null
          ? null
          : DateTime.tryParse('${j['scheduled_at']}'),
      updatedAt: j['updated_at'] == null
          ? null
          : DateTime.tryParse('${j['updated_at']}')?.toLocal(),
      prescriptionCount: (j['prescription_count'] as num?)?.toInt() ??
          (j['prescription'] is Map ? 1 : 0),
    );
  }

  DoctorCase copyWith({
    CaseStatus? status,
    DateTime? followUpDate,
    bool clearFollowUp = false,
  }) =>
      DoctorCase(
        id: id,
        appointmentId: appointmentId,
        farmerName: farmerName,
        farmName: farmName,
        flockSize: flockSize,
        birdAgeWeeks: birdAgeWeeks,
        breed: breed,
        mortalityCount: mortalityCount,
        symptoms: symptoms,
        diagnosis: diagnosis,
        treatmentPlan: treatmentPlan,
        diseaseTags: diseaseTags,
        urgency: urgency,
        status: status ?? this.status,
        feedNotes: feedNotes,
        vaccineHistory: vaccineHistory,
        biosecurityNotes: biosecurityNotes,
        warnings: warnings,
        nextSteps: nextSteps,
        createdAt: createdAt,
        followUpDate:
            clearFollowUp ? null : (followUpDate ?? this.followUpDate),
        prescription: prescription,
        stage: stage,
        editable: editable,
        consultationStatus: consultationStatus,
        mode: mode,
        scheduledAt: scheduledAt,
        updatedAt: updatedAt,
        prescriptionCount: prescriptionCount,
      );
}

// ── Chat ───────────────────────────────────────────────────────────────────────

/// One chat message. Kept in order and de-duplicated by the shared
/// [ChatTimeline] (lib/core/chat/chat_core.dart) — see CHAT_MESSAGE_STATE_FIX.md.
class ChatMessage implements ChatTimelineItem {
  /// Server id once confirmed; the client id while still sending/failed.
  @override
  final String id;
  @override
  final String? clientMessageId;
  final bool fromDoctor;
  final String content;
  final MessageType type;
  /// Server-persisted send time in the viewer's local zone (provisional
  /// device time only while [status] is `sending`/`failed`).
  @override
  final DateTime sentAt;
  final ChatSendStatus status;

  const ChatMessage({
    required this.id,
    required this.fromDoctor,
    required this.content,
    required this.type,
    required this.sentAt,
    this.clientMessageId,
    this.status = ChatSendStatus.sent,
  });

  @override
  ChatSendStatus get sendStatus => status;

  /// [myUserId] decides authorship for Socket.IO broadcasts, which carry
  /// `sender_id` but no viewer-relative `from_doctor`/`from_me`.
  factory ChatMessage.fromJson(Map<String, dynamic> j, {String? myUserId}) {
    final fromFlag = j['from_doctor'] ?? j['from_me'];
    return ChatMessage(
      id: '${j['id']}',
      clientMessageId: j['client_message_id']?.toString(),
      fromDoctor: fromFlag is bool
          ? fromFlag
          : (myUserId != null && '${j['sender_id']}' == myUserId),
      content: '${j['content'] ?? ''}',
      type: _messageType('${j['type'] ?? j['message_type']}'),
      // Was DateTime.parse(...) — a naive UTC value was read as local time.
      sentAt: ChatTime.parseServer(j['sent_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// The optimistic bubble: provisional local time until the server answers.
  factory ChatMessage.pending(String content, {required String clientMessageId}) =>
      ChatMessage(
        id: clientMessageId,
        clientMessageId: clientMessageId,
        fromDoctor: true,
        content: content,
        type: MessageType.text,
        sentAt: DateTime.now(),
        status: ChatSendStatus.sending,
      );

  ChatMessage withStatus(ChatSendStatus value) => ChatMessage(
        id: id,
        clientMessageId: clientMessageId,
        fromDoctor: fromDoctor,
        content: content,
        type: type,
        sentAt: sentAt,
        status: value,
      );
}

class ChatThread {
  final String id;
  final String farmerName;
  final String farmName;
  final String? lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
  final String? caseId;
  final List<ChatMessage> messages;

  const ChatThread({
    required this.id,
    required this.farmerName,
    required this.farmName,
    this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    this.caseId,
    required this.messages,
  });

  factory ChatThread.fromJson(Map<String, dynamic> j) => ChatThread(
      id: '${j['id']}',
      farmerName: '${j['farmer_name'] ?? ''}',
      farmName: '${j['farm_name'] ?? ''}',
      lastMessage: j['last_message']?.toString(),
      lastMessageAt: ChatTime.parseServer(j['last_message_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
      caseId: j['case_id']?.toString(),
      messages: ChatTimeline.mergePage(<ChatMessage>[],
          (j['messages'] as List? ?? [])
              .map((x) => ChatMessage.fromJson(Map<String, dynamic>.from(x as Map)))));

  ChatThread copyWith({
    List<ChatMessage>? messages,
    int? unreadCount,
    String? lastMessage,
    DateTime? lastMessageAt,
  }) =>
      ChatThread(
        id: id,
        farmerName: farmerName,
        farmName: farmName,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        unreadCount: unreadCount ?? this.unreadCount,
        caseId: caseId,
        messages: messages ?? this.messages,
      );
}

// ── Earnings & Ratings ────────────────────────────────────────────────────────

class EarningsRecord {
  final String id;
  final String farmerName;
  final String? caseId;
  final double amount;
  final double grossAmount;
  final double platformFee;
  final bool paymentReceived;
  final DateTime? paymentReceivedAt;
  final String payoutStatus;
  final DateTime date;
  final bool isPaid;
  final String description;

  const EarningsRecord({
    required this.id,
    required this.farmerName,
    this.caseId,
    required this.amount,
    this.grossAmount = 0,
    this.platformFee = 0,
    this.paymentReceived = false,
    this.paymentReceivedAt,
    this.payoutStatus = 'pending',
    required this.date,
    required this.isPaid,
    required this.description,
  });

  factory EarningsRecord.fromJson(Map<String, dynamic> j) => EarningsRecord(
      id: '${j['id']}',
      farmerName: '${j['farmer_name'] ?? ''}',
      caseId: j['case_id']?.toString(),
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      grossAmount: (j['gross_amount'] as num?)?.toDouble() ??
          (j['amount'] as num?)?.toDouble() ??
          0,
      platformFee: (j['platform_fee'] as num?)?.toDouble() ?? 0,
      paymentReceived: j['payment_received'] == true,
      paymentReceivedAt: j['payment_received_at'] == null
          ? null
          : DateTime.parse('${j['payment_received_at']}'),
      payoutStatus: '${j['payout_status'] ?? 'pending'}',
      date: DateTime.parse('${j['date']}'),
      isPaid: j['is_paid'] == true,
      description: '${j['description'] ?? ''}');
}

class FarmerRating {
  final String id;
  final String farmerName;
  final double rating;
  final String? review;
  final DateTime date;

  const FarmerRating({
    required this.id,
    required this.farmerName,
    required this.rating,
    this.review,
    required this.date,
  });

  factory FarmerRating.fromJson(Map<String, dynamic> j) => FarmerRating(
      id: '${j['id']}',
      farmerName: '${j['farmer_name'] ?? ''}',
      rating: (j['rating'] as num?)?.toDouble() ?? 0,
      review: j['review']?.toString(),
      date: DateTime.parse('${j['date']}'));
}

DoctorAvailability _availability(String v) =>
    {
      'available': DoctorAvailability.available,
      'busy': DoctorAvailability.busy
    }[v] ??
    DoctorAvailability.offline;
AppointmentMode _appointmentMode(String v) =>
    {
      'online': AppointmentMode.online,
      'offline': AppointmentMode.inPerson,
      'in_person': AppointmentMode.inPerson,
      'in-person': AppointmentMode.inPerson,
    }[v] ??
    AppointmentMode.inPerson;
AppointmentStatus _appointmentStatus(String v) =>
    {
      'pending': AppointmentStatus.pending,
      'requested': AppointmentStatus.pending,
      'accepted': AppointmentStatus.accepted,
      'in_progress': AppointmentStatus.inProgress,
      'rejected': AppointmentStatus.rejected,
      'rescheduled': AppointmentStatus.rescheduled,
      'reschedule_proposed': AppointmentStatus.rescheduled,
      'completed': AppointmentStatus.completed,
      'cancelled': AppointmentStatus.cancelled,
      'no_show': AppointmentStatus.noShow
    }[v] ??
    AppointmentStatus.pending;
CaseUrgency _caseUrgency(String v) =>
    {
      'moderate': CaseUrgency.moderate,
      'urgent': CaseUrgency.urgent,
      'emergency': CaseUrgency.emergency
    }[v] ??
    CaseUrgency.routine;
CaseStage _caseStage(String v) =>
    {
      'awaiting_acceptance': CaseStage.awaitingAcceptance,
      'closed': CaseStage.closed,
      'completed': CaseStage.completed,
      'prescribed': CaseStage.prescribed,
      'ended': CaseStage.ended,
    }[v] ??
    CaseStage.open;
CaseStatus _caseStatus(String v) =>
    {
      'in_progress': CaseStatus.inProgress,
      'follow_up': CaseStatus.followUp,
      'closed': CaseStatus.closed
    }[v] ??
    CaseStatus.open;
MessageType _messageType(String v) =>
    {'image': MessageType.image, 'file': MessageType.file}[v] ??
    MessageType.text;
