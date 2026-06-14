class ResearcherProfile {
  final String id;
  final String name;
  final String email;
  final String institution;
  final String department;
  final String specialty;
  final int yearsExperience;
  final List<String> researchInterests;
  final String bio;
  final bool isVerified;
  final String contactEmail;
  final String? orcid;
  final String? linkedIn;
  final int totalPublications;
  final int totalCitations;
  final int hIndex;

  const ResearcherProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.institution,
    required this.department,
    required this.specialty,
    required this.yearsExperience,
    required this.researchInterests,
    required this.bio,
    required this.isVerified,
    required this.contactEmail,
    this.orcid,
    this.linkedIn,
    this.totalPublications = 0,
    this.totalCitations = 0,
    this.hIndex = 0,
  });
}
