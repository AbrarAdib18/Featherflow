from django.contrib import admin
from django.urls import path, include
from django.views.generic import RedirectView

# Load the project-wide registry after Django's normal admin autodiscovery.
import api.admin_registry  # noqa: F401, E402
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('', RedirectView.as_view(url='/api/', permanent=False)),
    path('admin/', admin.site.urls),
    path('api/', include('api.urls')),
]
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
