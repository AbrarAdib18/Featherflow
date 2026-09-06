import json

from django.contrib import admin
from django.utils.html import format_html

from audit.admin_base import ModuleRecordAdmin
from audit.models import ActivityLog, AdminPanelRecord, SecurityFlag


@admin.register(AdminPanelRecord)
class AdminPanelRecordAdmin(admin.ModelAdmin):
    list_display = ('module', 'record_id', 'record_label', 'record_status', 'updated_at')
    list_filter = ('module', 'created_at', 'updated_at')
    search_fields = ('module', 'record_id', 'payload')
    readonly_fields = ('id', 'created_at', 'updated_at', 'formatted_payload')
    ordering = ('module', 'record_id')

    @admin.display(description='Label')
    def record_label(self, obj):
        return (obj.payload.get('name') or obj.payload.get('title') or
                obj.payload.get('subject') or obj.payload.get('user') or '—')

    @admin.display(description='Status')
    def record_status(self, obj):
        return obj.payload.get('status', '—')

    @admin.display(description='Formatted record data')
    def formatted_payload(self, obj):
        return format_html(
            '<pre style="white-space:pre-wrap">{}</pre>',
            json.dumps(obj.payload, indent=2, ensure_ascii=False, default=str),
        )


@admin.register(ActivityLog)
class ActivityLogAdmin(admin.ModelAdmin):
    list_display = ('created_at', 'user', 'module', 'action', 'entity_type', 'entity_id')
    list_filter = ('module', 'action', 'created_at')
    search_fields = ('user__email', 'module', 'action', 'entity_type', 'entity_id')
    readonly_fields = (
        'id', 'user', 'module', 'action', 'entity_type', 'entity_id',
        'old_values', 'new_values', 'ip_address', 'created_at',
    )
    ordering = ('-created_at',)

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return request.user.is_superuser


@admin.register(SecurityFlag)
class SecurityFlagAdmin(ModuleRecordAdmin):
    module_name = 'security-flags'
