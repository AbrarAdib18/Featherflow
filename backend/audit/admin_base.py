import json

from django.contrib import admin
from django.utils.html import format_html


class ModuleRecordAdmin(admin.ModelAdmin):
    """Admin view over one module stored in audit.AdminPanelRecord."""

    module_name = ''
    list_display = ('record_id', 'record_label', 'record_status', 'updated_at')
    search_fields = ('record_id', 'payload')
    readonly_fields = ('id', 'created_at', 'updated_at', 'formatted_payload')
    ordering = ('record_id',)

    def get_queryset(self, request):
        return super().get_queryset(request).filter(module=self.module_name)

    def save_model(self, request, obj, form, change):
        obj.module = self.module_name
        super().save_model(request, obj, form, change)

    @admin.display(description='Label')
    def record_label(self, obj):
        return (obj.payload.get('name') or obj.payload.get('title') or
                obj.payload.get('subject') or obj.payload.get('user') or
                obj.payload.get('customer') or '—')

    @admin.display(description='Status')
    def record_status(self, obj):
        return obj.payload.get('status', '—')

    @admin.display(description='Formatted live data')
    def formatted_payload(self, obj):
        return format_html(
            '<pre style="white-space:pre-wrap">{}</pre>',
            json.dumps(obj.payload, indent=2, ensure_ascii=False, default=str),
        )
