"""Admin Panel role-based access control.

One source of truth: a ``roles`` row with ``panel_type='admin'`` carries a
``tier_level`` (1 Super … 4 Support) and a ``permissions`` JSON map of
``{module: [action, ...]}``. ``admin_super`` uses the wildcard ``{"*": ["*"]}``.

Everything the admin views need for authorization lives here:
  * ``admin_roles(user)`` / ``admin_tier(user)`` / ``effective_permissions(user)``
  * tier predicates: ``is_super_admin`` / ``is_operations_admin`` /
    ``is_module_admin`` / ``is_support_agent``
  * ``can_perform_action(user, module, action)`` — the granular check
  * ``requires_approval(user, module, action, context)`` — sensitive-action gate
  * DRF permission classes ``IsAdminUser`` and ``ModulePermission``
"""

from functools import lru_cache

from rest_framework.permissions import BasePermission

# Canonical admin role names (match featherflow_schema.sql seed data).
ROLE_SUPER = 'admin_super'
ROLE_OPERATIONS = 'admin_operations'
ROLE_SUPPORT = 'admin_support'
ROLE_TEAM = 'admin_team'
LEGACY_OPERATIONS = 'admin'  # pre-RBAC generic admin role → treated as Operations

MODULE_ROLE = {
    'finance': 'admin_finance',
    'content': 'admin_content',
    'research': 'admin_research',
    'delivery': 'admin_delivery',
    'pharmacy': 'admin_pharmacy',
    'doctors': 'admin_doctor',
    'support': 'admin_support',
    'team': 'admin_team',
}

TIER_SUPER, TIER_OPERATIONS, TIER_MODULE, TIER_SUPPORT = 1, 2, 3, 4

# Actions the audit trail and permission maps recognise.
ACTIONS = {
    'view', 'create', 'edit', 'approve', 'reject', 'delete',
    'suspend', 'assign', 'export', 'refund', 'override',
}

# Endpoint module slug -> canonical permission-map module key. Several admin
# collection slugs share one permission domain (all article kinds -> "articles").
MODULE_ALIASES = {
    'users': 'users', 'team': 'team', 'access-logs': 'audit', 'audit-logs': 'audit',
    'doctors': 'doctors', 'consultations': 'doctors', 'consultation-disputes': 'doctors',
    'riders': 'delivery', 'delivery-orders': 'delivery', 'payouts': 'delivery',
    'pharmacies': 'pharmacy', 'medicines': 'pharmacy',
    'pharmacy-products': 'pharmacy', 'pharmacy-orders': 'pharmacy',
    'researchers': 'research', 'research-tags': 'research',
    'profile-change-applications': 'research',
    'articles': 'articles', 'research-papers': 'articles', 'disease-updates': 'articles',
    'innovations': 'articles', 'team-updates': 'articles', 'content-reports': 'articles',
    'community-reports': 'community', 'community-users': 'community',
    'payments': 'finance', 'subscription-plans': 'subscriptions', 'subscriptions': 'subscriptions',
    'support-tickets': 'support', 'security-flags': 'support',
    'diseases': 'settings',
    'approval-queue': 'approvals', 'escalations': 'escalations',
    'oversight': 'oversight', 'admins': 'team',
}


def canonical_module(module):
    return MODULE_ALIASES.get(module, module)


def admin_roles(user):
    """The user's admin-panel roles as ``Role`` objects (empty if none)."""
    if not user or not getattr(user, 'is_authenticated', False):
        return []
    return [r for r in user.roles.all() if r.panel_type == 'admin']


def is_admin(user):
    return bool(admin_roles(user))


def admin_tier(user):
    """Lowest (most privileged) tier across the user's admin roles; None if not an admin."""
    tiers = []
    for role in admin_roles(user):
        if role.tier_level:
            tiers.append(role.tier_level)
        elif role.name == ROLE_SUPER:
            tiers.append(TIER_SUPER)
        elif role.name in (ROLE_OPERATIONS, LEGACY_OPERATIONS):
            tiers.append(TIER_OPERATIONS)
        elif role.name == ROLE_SUPPORT:
            tiers.append(TIER_SUPPORT)
        else:
            tiers.append(TIER_MODULE)
    return min(tiers) if tiers else None


def effective_permissions(user):
    """Union of every admin role's permission map. ``{"*": ["*"]}`` short-circuits."""
    merged = {}
    for role in admin_roles(user):
        perms = role.permissions if isinstance(role.permissions, dict) else {}
        if perms.get('*') == ['*'] or '*' in perms.get('*', []):
            return {'*': ['*']}
        # Legacy 'admin' role may predate the permission seed — treat as Operations.
        if not perms and role.name == LEGACY_OPERATIONS:
            perms = _operations_fallback()
        for module, actions in perms.items():
            merged.setdefault(module, set()).update(actions)
    return {m: sorted(a) for m, a in merged.items()}


def _operations_fallback():
    return {
        'users': ['view', 'edit', 'approve', 'suspend', 'export'],
        'doctors': ['view', 'edit', 'approve', 'reject', 'suspend', 'export'],
        'delivery': ['view', 'edit', 'approve', 'reject', 'assign', 'export'],
        'pharmacy': ['view', 'edit', 'approve', 'reject', 'suspend', 'export'],
        'research': ['view', 'approve', 'reject'], 'articles': ['view', 'approve', 'reject'],
        'community': ['view', 'edit', 'reject', 'suspend', 'delete'], 'subscriptions': ['view', 'export'],
        'finance': ['view', 'export'], 'support': ['view', 'edit', 'assign', 'approve'],
        'team': ['view'], 'audit': ['view', 'export'],
        'approvals': ['view', 'approve', 'reject'], 'escalations': ['view', 'approve'],
        'oversight': ['view'], 'settings': ['view'],
    }


def can_perform_action(user, module, action):
    """True if any of the user's admin roles grants ``action`` on ``module``."""
    if not is_admin(user):
        return False
    perms = effective_permissions(user)
    if perms.get('*') == ['*']:
        return True
    key = canonical_module(module)
    allowed = set(perms.get(key, []))
    return action in allowed or '*' in allowed


def accessible_modules(user):
    perms = effective_permissions(user)
    if perms.get('*') == ['*']:
        return sorted({m for m in MODULE_ALIASES.values()} | {
            'users', 'doctors', 'delivery', 'pharmacy', 'research', 'articles',
            'community', 'subscriptions', 'finance', 'support', 'team', 'audit',
            'approvals', 'escalations', 'oversight', 'settings',
        })
    return sorted(m for m, acts in perms.items() if acts)


# ── tier predicates ─────────────────────────────────────────────────────────

def is_super_admin(user):
    return admin_tier(user) == TIER_SUPER


def is_operations_admin(user):
    """Operations tier *or above* (Super counts)."""
    tier = admin_tier(user)
    return tier is not None and tier <= TIER_OPERATIONS


def is_module_admin(user, module=None):
    if not is_admin(user):
        return False
    if module is None:
        return admin_tier(user) == TIER_MODULE
    return can_perform_action(user, module, 'view')


def is_support_agent(user):
    return admin_tier(user) == TIER_SUPPORT


# ── sensitive-action gate ───────────────────────────────────────────────────

REFUND_APPROVAL_THRESHOLD = 5000  # BDT — refunds/payouts above this need Operations+


def requires_approval(user, module, action, context=None):
    """Return the tier required to run this action now, or None if the user may
    run it directly. ``context`` carries hints (amount, target_verified, ...)."""
    context = context or {}
    tier = admin_tier(user) or TIER_SUPPORT
    key = canonical_module(module)

    needed = None
    if action == 'delete' and key in ('team', 'users') and context.get('target_is_admin'):
        needed = TIER_SUPER
    elif action == 'override':
        needed = TIER_SUPER
    elif action == 'assign' and key == 'team' and context.get('is_role_change'):
        needed = TIER_SUPER
    elif action == 'suspend' and context.get('target_verified'):
        needed = TIER_OPERATIONS
    elif action == 'refund' and float(context.get('amount') or 0) > REFUND_APPROVAL_THRESHOLD:
        needed = TIER_OPERATIONS

    if needed is None or tier <= needed:
        return None
    return needed


# ── DRF permission classes ──────────────────────────────────────────────────

class IsAdminUser(BasePermission):
    """Authenticated user holding at least one active, approved admin role."""

    message = 'An active admin account is required.'

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated and is_admin(user)):
            return False
        if user.account_status == 'suspended':
            self.message = 'This admin account is suspended.'
            return False
        profile = getattr(user, 'admin_profile', None)
        if profile is not None and (profile.is_suspended or profile.approval_status == 'pending'):
            self.message = (
                'This admin account is awaiting approval.'
                if profile.approval_status == 'pending' else 'This admin account is suspended.'
            )
            return False
        return True


class ModulePermission(BasePermission):
    """Use on a view that sets ``admin_module`` and ``admin_action`` attributes."""

    message = 'You do not have permission for this module action.'

    def has_permission(self, request, view):
        if not IsAdminUser().has_permission(request, view):
            self.message = IsAdminUser().message
            return False
        module = getattr(view, 'admin_module', None)
        action = getattr(view, 'admin_action', 'view')
        if module is None:
            return True
        return can_perform_action(request.user, module, action)
