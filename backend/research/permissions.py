from rest_framework.permissions import BasePermission

from subscriptions.permissions import has_feature

RESEARCH_FEATURE = 'researcher_panel'
CONTENT_ADMIN_ROLES = {'admin_super', 'admin_research', 'admin_content'}

# Trust-critical researcher_profiles fields — once the profile is verified,
# these are read-only and can only change through a ProfileChangeApplication
# reviewed by a content/research/super admin.
VERIFIED_PROFILE_FIELDS = {
    'institution_name', 'institutional_email', 'department', 'highest_degree',
    'field_of_study', 'university_name', 'graduation_year', 'research_role_type',
    'areas_of_expertise', 'poultry_specific_experience', 'ethics_certificate_url',
    'conflict_of_interest_declaration', 'publication_consent', 'ip_agreement',
}


class IsResearcher(BasePermission):
    """Any user with the researcher role — used for profile access, which a
    researcher must be able to see/edit even before verification."""

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and (
            user.is_superuser or user.roles.filter(name='researcher').exists()
        ))


def is_verified_researcher(user):
    if not user or not user.is_authenticated:
        return False
    if user.is_superuser:
        return True
    if not user.roles.filter(name='researcher').exists():
        return False
    profile = getattr(user, 'researcher_profile', None)
    return bool(profile and profile.is_verified)


def is_research_content_admin(user):
    return bool(user and user.is_authenticated and (
        user.is_superuser or user.roles.filter(name__in=CONTENT_ADMIN_ROLES).exists()
    ))


def has_research_subscription(user):
    return has_feature(user, RESEARCH_FEATURE)
