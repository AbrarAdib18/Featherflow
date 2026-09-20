"""Canonical poultry vocabulary shared across apps.

Bird type previously had four divergent definitions (farmers.farm_views,
feed.models.FeedingGuideline, feed_catalogue.models.FeedProduct, plus two DB
CHECK constraints). They disagreed on 'hatchery', which meant a flock could be
created with a bird type that no feeding guideline could ever match — the feed
chart came back empty and feed notifications skipped the flock silently.

'hatchery' is a FARM type, not a bird type. It stays in Farm.FARM_TYPES and is
excluded here; farmer_panel_integrity_extension.sql migrates existing
'hatchery' flocks to 'other'.
"""

# Canonical flock/bird types. Order is the display order in pickers.
BIRD_TYPE_VALUES = ('broiler', 'layer', 'chick', 'breeder', 'other')

BIRD_TYPE_LABELS = {
    'broiler': 'Broiler',
    'layer': 'Layer',
    'chick': 'Chick',
    'breeder': 'Breeder',
    'other': 'Other',
}

# Django `choices` form, for model fields and serializers.
BIRD_TYPE_CHOICES = [(value, BIRD_TYPE_LABELS[value]) for value in BIRD_TYPE_VALUES]

# Membership-test form, for the hand-rolled view validation in farmers/.
BIRD_TYPES = set(BIRD_TYPE_VALUES)


def bird_type_options():
    """Serialisable list for clients, so pickers render server-owned labels."""
    return [{'value': value, 'label': BIRD_TYPE_LABELS[value]} for value in BIRD_TYPE_VALUES]
