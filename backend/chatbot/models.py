from audit.models import AdminPanelRecord

class ChatbotSession(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Chatbot sessions'

class ChatbotMessage(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Chatbot messages'
