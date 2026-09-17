"""Single source of truth for "is this account verified?" (Priority 2).

Before this module, "verified" was answered differently in five+ places —
``User.account_status`` (the only field that actually gates login),
``User.is_verified`` (professional approval *and*, until this pass, an
unrelated community-badge toggle), and each role profile's own
``is_verified``/``approved_by_admin`` field, updated by a different, often
incomplete, subset of admin-panel actions. See ``FEED_AND_DATA_INTEGRITY_AUDIT.md``
Priority 2 for the specific desync bugs this replaces.

``compute_verification_status(user)`` returns one payload with three
independent, clearly-labelled axes so a UI never has to guess which raw flag
answers "am I verified": contact (email/phone OTP), professional_approval
(role-specific, or ``not_required`` for roles with no approval gate), and
documents (aggregated from ``SignupDocument`` review state).
"""
from verification.models import SignupDocument

# Document types that are just photos, not credentials an admin reviews.
_NON_CREDENTIAL_DOCUMENT_TYPES = {'profile_photo', 'farm_photo'}

# role name -> (profile relation name, verified-flag attribute) for roles
# whose approval is tracked on a boolean profile field.
_BOOLEAN_APPROVAL_ROLES = {
    'doctor': ('doctor_profile', 'is_verified'),
    'pharmacy': ('pharmacy_organization', 'is_verified'),
    'researcher': ('researcher_profile', 'is_verified'),
}


def _contact_status(user):
    return {
        'email_verified': bool(user.email_verified_at),
        'phone_verified': bool(user.phone_verified_at),
    }


def _professional_approval(user, role_names):
    """Returns {'status': ..., 'message': ...}.

    status in: not_required | pending | approved | rejected | suspended.
    'rejected' is only distinguishable for admin-staff (AdminProfile has a
    real ``approval_status`` field); every other role's admin actions collapse
    reject/suspend into the same ``account_status='suspended'`` value, so both
    surface as 'suspended' — that's what the underlying data actually
    supports today (see the audit doc), not a display bug.
    """
    if 'farmer' in role_names:
        return {
            'status': 'not_required',
            'message': 'Farmer accounts are active immediately — no professional approval is required.',
        }

    if 'admin' in role_names or any(r.startswith('admin_') for r in role_names):
        profile = getattr(user, 'admin_profile', None)
        if profile is None:
            return {'status': 'not_required', 'message': 'No admin-staff application on file.'}
        mapping = {
            'pending': ('pending', 'Your staff application is pending review.'),
            'approved': ('approved', 'Your staff application has been approved.'),
            'rejected': ('rejected', 'Your staff application was rejected.'),
            'suspended': ('suspended', 'Your staff access has been suspended.'),
        }
        status, message = mapping.get(profile.approval_status, ('pending', 'Your staff application is pending review.'))
        return {'status': status, 'message': message}

    if 'delivery' in role_names:
        profile = getattr(user, 'delivery_profile', None)
        if profile is None:
            return {'status': 'not_required', 'message': 'No delivery-rider application on file.'}
        if profile.approved_by_admin_id is not None and user.account_status != 'suspended':
            return {'status': 'approved', 'message': 'Your delivery rider application has been approved.'}
        if user.account_status == 'suspended':
            return {'status': 'suspended', 'message': 'Your delivery rider account has been suspended.'}
        return {'status': 'pending', 'message': 'Your delivery rider application is pending review.'}

    for role, (relation, flag) in _BOOLEAN_APPROVAL_ROLES.items():
        if role not in role_names:
            continue
        profile = getattr(user, relation, None)
        if profile is None:
            return {'status': 'not_required', 'message': f'No {role} application on file.'}
        verified = bool(getattr(profile, flag))
        label = {'doctor': 'vet', 'pharmacy': 'pharmacy', 'researcher': 'researcher'}[role]
        if verified and user.account_status != 'suspended':
            return {'status': 'approved', 'message': f'Your {label} application has been approved.'}
        if user.account_status == 'suspended':
            return {'status': 'suspended', 'message': f'Your {label} account has been suspended.'}
        return {'status': 'pending', 'message': f'Your {label} application is pending review.'}

    return {'status': 'not_required', 'message': 'No professional approval is required for this account.'}


def _documents_status(user):
    docs = list(SignupDocument.objects.filter(user=user)
                .exclude(document_type__in=_NON_CREDENTIAL_DOCUMENT_TYPES))
    if not docs:
        return {'status': 'not_applicable', 'message': 'No documents requiring review were submitted.',
                'total': 0, 'verified_count': 0}
    verified_count = sum(1 for d in docs if d.is_verified)
    if verified_count == len(docs):
        status, message = 'verified', 'All submitted documents have been verified.'
    elif verified_count > 0:
        status, message = 'partial', 'Some of your documents are verified; others are still awaiting review.'
    else:
        status, message = 'pending', 'Documents awaiting review.'
    return {'status': status, 'message': message, 'total': len(docs), 'verified_count': verified_count}


def compute_verification_status(user):
    role_names = set(getattr(user, 'role_names', []) or [r.name for r in user.roles.all()])
    contact = _contact_status(user)
    professional = _professional_approval(user, role_names)
    documents = _documents_status(user)
    account_active = user.account_status == 'active'

    messages = []
    messages.append('Email verified.' if contact['email_verified'] else 'Email verification pending.')
    messages.append('Phone verified.' if contact['phone_verified'] else 'Phone verification pending.')
    if professional['status'] != 'not_required':
        messages.append(professional['message'])
    if documents['status'] not in ('not_applicable',):
        messages.append(documents['message'])
    messages.append('Account active.' if account_active else
                     ('Account suspended.' if user.account_status == 'suspended' else 'Account pending activation.'))

    return {
        'contact': contact,
        'professional_approval': professional,
        'documents': documents,
        'account_active': account_active,
        'account_status': user.account_status,
        'messages': messages,
    }
