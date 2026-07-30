from django.urls import path
from .views import dashboard, expenses, revenues, loans, calculate_tax, expense_status, pay_tax
urlpatterns=[
    path('',dashboard),path('expenses/',expenses),path('revenues/',revenues),
    path('loans/',loans),path('expense-status/',expense_status),
    path('tax/calculate/',calculate_tax),path('tax/pay/',pay_tax),
]
