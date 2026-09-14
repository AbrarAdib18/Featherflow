from django.contrib import admin
from django.urls import path, include
from django.views.generic import RedirectView

# Load the project-wide registry after Django's normal admin autodiscovery.
import api.admin_registry  # noqa: F401, E402
from django.conf import settings
from django.conf.urls.static import static

from api.health import liveness, readiness

urlpatterns = [
    path('', RedirectView.as_view(url='/api/', permanent=False)),
    # Root-level, unversioned — the conventional path most load balancers /
    # container orchestrators / uptime monitors are configured to probe.
    path('healthz/', liveness, name='healthz'),
    path('readyz/', readiness, name='readyz'),
    path('admin/', admin.site.urls),
    path('api/', include('api.urls')),
]
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
