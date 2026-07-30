from django.contrib import admin
from users.models import User

@admin.register(User)
class UserAdmin(admin.ModelAdmin):
    list_display = ('email', 'full_name', 'phone', 'account_status', 'is_verified', 'is_staff')
    search_fields = ('email', 'full_name', 'phone')
