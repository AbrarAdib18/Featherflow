from django.contrib import admin
from audit.admin_base import ModuleRecordAdmin
from messaging.models import Conversation, Message

@admin.register(Conversation)
class ConversationAdmin(ModuleRecordAdmin): module_name = 'conversations'

@admin.register(Message)
class MessageAdmin(ModuleRecordAdmin): module_name = 'messages'
