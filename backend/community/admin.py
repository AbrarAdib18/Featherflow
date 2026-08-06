from django.contrib import admin
from audit.admin_base import ModuleRecordAdmin
from community.models import CommunityMember, CommunityReport

@admin.register(CommunityReport)
class CommunityReportAdmin(ModuleRecordAdmin):
    module_name = 'community-reports'

@admin.register(CommunityMember)
class CommunityMemberAdmin(ModuleRecordAdmin):
    module_name = 'community-users'
