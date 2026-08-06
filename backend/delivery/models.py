from audit.models import AdminPanelRecord


class DeliveryOrder(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name = 'Delivery order'
        verbose_name_plural = 'Delivery orders'


class DeliveryRider(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name = 'Delivery rider'
        verbose_name_plural = 'Delivery riders'
