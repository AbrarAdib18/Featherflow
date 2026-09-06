from django.urls import path

from research.views import (
    bookmarks, change_applications, collection, detail, profile, submit_review,
    tag_options, toggle_bookmark, upload_pdf, versions,
)

urlpatterns = [
    path('profile/', profile),
    path('profile/change-applications/', change_applications),
    path('tag-options/', tag_options),
    path('upload-pdf/', upload_pdf),
    path('bookmark/', toggle_bookmark),
    path('bookmarks/', bookmarks),
    path('<str:kind>/', collection),
    path('<str:kind>/<uuid:pk>/', detail),
    path('<str:kind>/<uuid:pk>/submit-review/', submit_review),
    path('<str:kind>/<uuid:pk>/versions/', versions),
]
