from django.urls import path

from . import owner_chat_views, owner_views

urlpatterns = [
    path('profile/', owner_views.profile),
    path('chat/', owner_chat_views.owner_conversation),
    path('chat/<uuid:conversation_id>/', owner_chat_views.owner_conversation_detail),
]
