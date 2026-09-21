// Unit tests for DoctorProfile.ratingLabel — the small computed property
// that decides what (if anything) renders beside the doctor's name in the
// dashboard header. Covers the three states called out in
// DOCTOR_DASHBOARD_PROFILE_AND_RATING.md: no ratings, one rating, many
// ratings — independent of any widget tree or DoctorSession singleton state.
import 'package:flutter_test/flutter_test.dart';

import 'package:featherflow/features/doctor/data/models/doctor_models.dart';

DoctorProfile _profile({required double rating, required int totalRatings}) =>
    DoctorProfile(
      id: 'd1',
      name: 'Dr Test',
      specialty: 'Poultry',
      licenseNo: 'LIC-1',
      phone: '01700000000',
      email: 'doc@example.com',
      rating: rating,
      totalRatings: totalRatings,
      isVerified: true,
      availability: DoctorAvailability.available,
    );

void main() {
  group('DoctorProfile.ratingLabel', () {
    test('no ratings yet -> null (hidden, never shows 0.0)', () {
      final profile = _profile(rating: 0, totalRatings: 0);
      expect(profile.ratingLabel, isNull);
    });

    test('one rating -> shows that rating, rounded to one decimal', () {
      final profile = _profile(rating: 5.0, totalRatings: 1);
      expect(profile.ratingLabel, '5.0');
    });

    test('many ratings -> shows the average, rounded to one decimal', () {
      final profile = _profile(rating: 4.666666, totalRatings: 128);
      expect(profile.ratingLabel, '4.7');
    });

    test('exact tenths are not padded with extra precision', () {
      final profile = _profile(rating: 4.5, totalRatings: 12);
      expect(profile.ratingLabel, '4.5');
    });
  });
}
