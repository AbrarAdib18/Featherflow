from audit.models import AdminPanelRecord

class SubscriptionPlan(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Subscription plans'

class Subscription(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'User subscriptions'
