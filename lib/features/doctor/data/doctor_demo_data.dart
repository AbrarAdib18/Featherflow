import 'models/doctor_models.dart';

/// Neutral placeholder shown only until the real profile arrives from
/// `/api/doctor/dashboard/`. It deliberately carries NO demo numbers: the doctor
/// panel used to start with hard-coded clients, cases and earnings that stayed
/// on screen whenever the API failed (F-008), so a real doctor could mistake
/// fake data for real data. Appointments, cases, chats and earnings now start
/// empty and are filled only from the API.
const doctorProfile = DoctorProfile(
  id: '',
  name: 'Doctor',
  specialty: '',
  licenseNo: '',
  phone: '',
  email: '',
  rating: 0,
  totalRatings: 0,
  isVerified: false,
  availability: DoctorAvailability.available,
);
