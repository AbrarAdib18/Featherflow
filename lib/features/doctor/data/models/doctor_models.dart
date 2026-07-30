enum AppointmentMode { online, offline, inPerson }

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
}

class DoctorPrescription {
  final String id;
  final String caseId;
  final List<MedicineSuggestion> medicines;
  final String? dosageNotes;
  final String? followUpInstructions;
  final String? referredTo;
  final DateTime createdAt;

  const DoctorPrescription({
    required this.id,
    required this.caseId,
    required this.medicines,
    this.dosageNotes,
    this.followUpInstructions,
    this.referredTo,
    required this.createdAt,
  });
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
  final DateTime date;
  final bool isPaid;
  final String description;

  const EarningsRecord({
    required this.id,
    required this.farmerName,
    this.caseId,
    required this.amount,
    required this.date,
    required this.isPaid,
    required this.description,
  });
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
}
