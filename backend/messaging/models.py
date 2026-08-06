from audit.models import AdminPanelRecord

class Conversation(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Conversations'

class Message(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Messages'
