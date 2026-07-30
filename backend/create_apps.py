from pathlib import Path

base = Path(__file__).resolve().parent
apps = [
    'subscriptions', 'payments', 'profiles', 'farms', 'workers', 'feed',
    'expenses', 'disease', 'chatbot', 'consultations', 'messaging',
    'pharmacy', 'delivery', 'community', 'articles', 'notifications', 'audit'
]

for app in apps:
    appdir = base / app
    appdir.mkdir(exist_ok=True)
    (appdir / '__init__.py').write_text('')
    (appdir / 'apps.py').write_text(
        f"from django.apps import AppConfig\n\n"
        f"class {app.capitalize()}Config(AppConfig):\n"
        f"    default_auto_field = 'django.db.models.BigAutoField'\n"
        f"    name = '{app}'\n"
    )
    (appdir / 'models.py').write_text(
        f"from django.db import models\n\n"
        f"# TODO: implement models for the {app} app based on featherflow_schema.sql\n\n"
        f"class Placeholder(models.Model):\n"
        f"    created_at = models.DateTimeField(auto_now_add=True)\n\n"
        f"    class Meta:\n"
        f"        abstract = True\n"
    )
    migrations = appdir / 'migrations'
    migrations.mkdir(exist_ok=True)
    (migrations / '__init__.py').write_text('')
