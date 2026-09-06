from django.urls import path

from articles.views import detail, feed, report_content, tags

urlpatterns = [
    path('all/', feed),
    path('tags/', tags),
    path('report/', report_content),
    path('<str:content_type>/<uuid:content_id>/', detail),
]
