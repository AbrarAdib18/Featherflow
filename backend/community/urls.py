from django.urls import path
from .views import feed,react,comment,bookmark,follow,upload,notifications
urlpatterns=[path('',feed),path('react/',react),path('comment/',comment),path('bookmark/',bookmark),path('follow/',follow),path('upload/',upload),path('notifications/',notifications)]
