"""Register every concrete project model that does not define custom admin UI."""

from django.apps import apps
from django.contrib import admin
from django.db import models


def _field_names(model):
    return [
        field.name for field in model._meta.get_fields()
        if getattr(field, 'concrete', False) and not field.many_to_many
    ]


def _display_fields(model):
    names = _field_names(model)
    preferred = [
        name for name in [
            'id', 'name', 'title', 'email', 'full_name', 'status',
            'account_status', 'user', 'created_at', 'updated_at',
        ] if name in names
    ]
    remaining = [name for name in names if name not in preferred]
    return tuple((preferred + remaining)[:8]) or ('__str__',)


def _search_fields(model):
    return tuple(
        field.name for field in model._meta.fields
        if isinstance(field, (models.CharField, models.TextField, models.EmailField))
    )[:8]


def _filter_fields(model):
    filters = []
    for field in model._meta.fields:
        if (isinstance(field, models.BooleanField) or field.choices or
                field.name in {'status', 'account_status', 'module', 'created_at'}):
            filters.append(field.name)
    return tuple(filters[:6])


def register_all_models():
    for model in apps.get_models():
        if model._meta.abstract or model._meta.proxy:
            continue
        try:
            admin.site.register(
                model,
                type(
                    f'{model.__name__}AutoAdmin',
                    (admin.ModelAdmin,),
                    {
                        'list_display': _display_fields(model),
                        'search_fields': _search_fields(model),
                        'list_filter': _filter_fields(model),
                        'list_per_page': 50,
                        'show_full_result_count': False,
                    },
                ),
            )
        except admin.sites.AlreadyRegistered:
            pass


register_all_models()
