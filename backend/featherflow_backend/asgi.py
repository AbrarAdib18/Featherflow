import os
import socketio
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
application = get_asgi_application()

from messaging.realtime import sio

application = socketio.ASGIApp(sio, application)
