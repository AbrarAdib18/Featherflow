/// How a consultation is delivered. This is independent of the doctor's
/// current availability/presence status.
enum AppointmentMode { online, inPerson }

enum AppointmentStatus {
  pending,
  accepted,
  rejected,
  rescheduled,
  completed,
  noShow
}

enum DoctorAvailability { available, busy, offline }

enum CaseUrgency { routine, moderate, urgent, emergency }

/// Status flows: open → inProgress → followUp → closed
enum CaseStatus { open, inProgress, followUp, closed }

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
}

// ── Appointment ────────────────────────────────────────────────────────────────

class DoctorAppointment {
  final String id;
  final String farmerName;
  final String farmName;
  final String farmerPhone;
  final DateTime scheduledAt;
  final AppointmentMode mode;
  final AppointmentStatus status;
  final bool isUrgent;
  final String? caseId;
  final double fee;
  final String? notes;

  const DoctorAppointment({
    required this.id,
    required this.farmerName,
    required this.farmName,
    required this.farmerPhone,
    required this.scheduledAt,
    required this.mode,
    required this.status,
    required this.isUrgent,
    this.caseId,
    required this.fee,
    this.notes,
  });

  factory DoctorAppointment.fromJson(Map<String, dynamic> j) =>
      DoctorAppointment(
        id: '${j['id']}',
        farmerName: '${j['farmer_name'] ?? ''}',
        farmName: '${j['farm_name'] ?? ''}',
        farmerPhone: '${j['farmer_phone'] ?? ''}',
        scheduledAt: DateTime.parse('${j['scheduled_at']}'),
        mode: _appointmentMode('${j['mode']}'),
        status: _appointmentStatus('${j['status']}'),
        isUrgent: j['is_urgent'] == true,
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
        mode: mode,
        status: status ?? this.status,
        isUrgent: isUrgent,
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

  const DoctorPrescription({
    required this.id,
    required this.caseId,
    required this.medicines,
    this.dosageNotes,
    this.caseAdvice,
    this.followUpInstructions,
    this.referredTo,
    required this.createdAt,
  });

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
          createdAt: DateTime.parse('${j['created_at']}'));
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
  });

  factory DoctorCase.fromJson(Map<String, dynamic> j) => DoctorCase(
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
      status: _caseStatus('${j['status']}'),
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
          : null);

  DoctorCase copyWith({
    CaseStatus? status,
    DateTime? followUpDate,
    bool clearFollowUp = false,
    DoctorPrescription? prescription,
    String? diagnosis,
    String? treatmentPlan,
    String? warnings,
    String? nextSteps,
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
        diagnosis: diagnosis ?? this.diagnosis,
        treatmentPlan: treatmentPlan ?? this.treatmentPlan,
        diseaseTags: diseaseTags,
        urgency: urgency,
        status: status ?? this.status,
        feedNotes: feedNotes,
        vaccineHistory: vaccineHistory,
        biosecurityNotes: biosecurityNotes,
        warnings: warnings ?? this.warnings,
        nextSteps: nextSteps ?? this.nextSteps,
        createdAt: createdAt,
        followUpDate:
            clearFollowUp ? null : (followUpDate ?? this.followUpDate),
        prescription: prescription ?? this.prescription,
      );
}

// ── Chat ───────────────────────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final bool fromDoctor;
  final String content;
  final MessageType type;
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.fromDoctor,
    required this.content,
    required this.type,
    required this.sentAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
      id: '${j['id']}',
      fromDoctor: j['from_doctor'] == true,
      content: '${j['content'] ?? ''}',
      type: _messageType('${j['type']}'),
      sentAt: DateTime.parse('${j['sent_at']}'));
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
      lastMessageAt: DateTime.parse('${j['last_message_at']}'),
      unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
      caseId: j['case_id']?.toString(),
      messages: (j['messages'] as List? ?? [])
          .map((x) => ChatMessage.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList());

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
      'accepted': AppointmentStatus.accepted,
      'rejected': AppointmentStatus.rejected,
      'rescheduled': AppointmentStatus.rescheduled,
      'reschedule_proposed': AppointmentStatus.rescheduled,
      'completed': AppointmentStatus.completed,
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
