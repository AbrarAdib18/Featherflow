from django.contrib import admin
from audit.admin_base import ModuleRecordAdmin
from chatbot.models import ChatbotMessage, ChatbotSession

@admin.register(ChatbotSession)
class ChatbotSessionAdmin(ModuleRecordAdmin): module_name = 'chatbot-sessions'

@admin.register(ChatbotMessage)
class ChatbotMessageAdmin(ModuleRecordAdmin): module_name = 'chatbot-messages'
