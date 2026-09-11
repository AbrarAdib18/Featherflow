import os
from pathlib import Path
from datetime import timedelta
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent

# Keep local database credentials in backend/.env (never commit that file).
load_dotenv(BASE_DIR / '.env')


def required_env(name):
    value = os.environ.get(name, '').strip()
    if not value:
        raise RuntimeError(f'{name} must be set in backend/.env')
    return value

SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', 'django-insecure-change-me')
DEBUG = os.environ.get('DJANGO_DEBUG', 'True') == 'True'
ALLOWED_HOSTS = os.environ.get('DJANGO_ALLOWED_HOSTS', 'localhost,127.0.0.1').split(',')

INSTALLED_APPS = [
    'corsheaders',
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    'rest_framework',
    'rest_framework_simplejwt',

    'api',
    'users',
    'subscriptions',
    'payments',
    'profiles',
    'farms',
    'farmers',
    'workers',
    'feed',
    'expenses',
    'disease',
    'ml',
    'chatbot',
    'consultations',
    'doctor',
    'messaging',
    'pharmacy',
    'delivery',
    'community',
    'articles',
    'research',
    'notifications',
    'audit',
    'verification',
    'tax',
    'billing',
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'featherflow_backend.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'featherflow_backend.wsgi.application'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': required_env('POSTGRES_DB'),
        'USER': required_env('POSTGRES_USER'),
        'PASSWORD': required_env('POSTGRES_PASSWORD'),
        'HOST': required_env('POSTGRES_HOST'),
        'PORT': os.environ.get('POSTGRES_PORT', '5432'),
        'CONN_MAX_AGE': int(os.environ.get('POSTGRES_CONN_MAX_AGE', '60')),
        'OPTIONS': {
            'sslmode': os.environ.get('POSTGRES_SSLMODE', 'prefer'),
        },
    }
}

DATABASE_ROUTERS = ['featherflow_backend.database_router.ExistingSchemaRouter']

TIME_ZONE = 'Asia/Dhaka'

GOOGLE_MAPS_API_KEY = os.environ.get('GOOGLE_MAPS_API_KEY', '')

AUTH_USER_MODEL = 'users.User'

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        # Password-version-aware — invalidates old tokens after a reset.
        'verification.auth.VersionedJWTAuthentication',
        'rest_framework.authentication.SessionAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
    'DEFAULT_THROTTLE_CLASSES': [
        'api.throttling.ScopedApiThrottle',
    ],
    'DEFAULT_THROTTLE_RATES': {
        # Admin panel: generous for dashboards/lists, tighter for writes and exports.
        'admin_read': os.environ.get('THROTTLE_ADMIN_READ', '600/min'),
        'admin_write': os.environ.get('THROTTLE_ADMIN_WRITE', '120/min'),
        'admin_export': os.environ.get('THROTTLE_ADMIN_EXPORT', '20/min'),
        'admin_poll': os.environ.get('THROTTLE_ADMIN_POLL', '240/min'),
        # Disease-detection inference is CPU-heavy — cap it per farmer.
        'disease_predict': os.environ.get('THROTTLE_DISEASE_PREDICT', '30/hour'),
        # Anonymous auth surface — blunt mass signup / credential stuffing.
        'auth_register': os.environ.get('THROTTLE_AUTH_REGISTER', '10/hour'),
        'auth_login': os.environ.get('THROTTLE_AUTH_LOGIN', '20/min'),
        'auth_upload': os.environ.get('THROTTLE_AUTH_UPLOAD', '30/hour'),
        # OTP verification + password reset (per IP; finer per-identity limits
        # are enforced in verification/otp.py).
        'otp_request': os.environ.get('THROTTLE_OTP_REQUEST', '15/hour'),
        'otp_confirm': os.environ.get('THROTTLE_OTP_CONFIRM', '30/hour'),
        'password_reset': os.environ.get('THROTTLE_PASSWORD_RESET', '10/hour'),
        'document_fetch': os.environ.get('THROTTLE_DOCUMENT_FETCH', '120/hour'),
        # Authenticated profile-photo changes + subscription checkout.
        'profile_photo': os.environ.get('THROTTLE_PROFILE_PHOTO', '20/hour'),
        'payment_write': os.environ.get('THROTTLE_PAYMENT_WRITE', '60/hour'),
    },
}

# ── Contact verification / password reset ────────────────────────────────────
# Expose the OTP in the API response (dev / manual QA only — MUST be false in
# production or codes leak to anyone who can hit the endpoint).
OTP_EXPOSE_CODES = os.environ.get(
    'OTP_EXPOSE_CODES', 'True' if DEBUG else 'False') == 'True'
# Hard gates on the signup flow. Email is on by default; phone needs a real SMS
# provider (see verification/delivery.py) so it is opt-in.
SIGNUP_REQUIRE_EMAIL_VERIFICATION = os.environ.get(
    'SIGNUP_REQUIRE_EMAIL_VERIFICATION', 'True') == 'True'
SIGNUP_REQUIRE_PHONE_VERIFICATION = os.environ.get(
    'SIGNUP_REQUIRE_PHONE_VERIFICATION', 'False') == 'True'
SMS_BACKEND = os.environ.get('SMS_BACKEND', 'console')
# Uploaded signup documents — private, never under MEDIA_URL.
PRIVATE_MEDIA_ROOT = BASE_DIR / 'private_media'

# ── Payments / subscription billing ─────────────────────────────────────────
# 'dev'  — simulated checkout, NO real money. The client picks the outcome
#          (success / failure / cancel) and the subscription activates only on
#          a simulated success. Clearly labelled in the API + UI.
# 'live' — real provider. Confirmation must come from a verified webhook
#          (billing/webhooks.py); the dev-confirm endpoint is refused.
# Auto-upgrades to 'live' only when a provider secret is actually configured.
_PAYMENT_PROVIDER_KEYS = (
    os.environ.get('STRIPE_SECRET_KEY', ''),
    os.environ.get('BKASH_APP_SECRET', ''),
    os.environ.get('NAGAD_MERCHANT_PRIVATE_KEY', ''),
)
BILLING_MODE = os.environ.get(
    'BILLING_MODE', 'live' if any(_PAYMENT_PROVIDER_KEYS) else 'dev').lower()
STRIPE_SECRET_KEY = os.environ.get('STRIPE_SECRET_KEY', '')
STRIPE_PUBLISHABLE_KEY = os.environ.get('STRIPE_PUBLISHABLE_KEY', '')
STRIPE_WEBHOOK_SECRET = os.environ.get('STRIPE_WEBHOOK_SECRET', '')
BKASH_APP_KEY = os.environ.get('BKASH_APP_KEY', '')
BKASH_APP_SECRET = os.environ.get('BKASH_APP_SECRET', '')
BKASH_USERNAME = os.environ.get('BKASH_USERNAME', '')
BKASH_PASSWORD = os.environ.get('BKASH_PASSWORD', '')
BKASH_BASE_URL = os.environ.get('BKASH_BASE_URL', 'https://tokenized.sandbox.bka.sh')
NAGAD_MERCHANT_ID = os.environ.get('NAGAD_MERCHANT_ID', '')
NAGAD_MERCHANT_PRIVATE_KEY = os.environ.get('NAGAD_MERCHANT_PRIVATE_KEY', '')
NAGAD_PUBLIC_KEY = os.environ.get('NAGAD_PUBLIC_KEY', '')
NAGAD_BASE_URL = os.environ.get('NAGAD_BASE_URL', 'https://api.mynagad.com/api/dfs')

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(days=7),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=30),
    'AUTH_HEADER_TYPES': ('Bearer',),
}

CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True
SOCKET_IO_ALLOWED_ORIGINS = [
    value.strip() for value in os.environ.get(
        'SOCKET_IO_ALLOWED_ORIGINS',
        'http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000,http://127.0.0.1:8080',
    ).split(',') if value.strip()
]

STATIC_URL = '/static/'
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

# Email delivery.
#   * Set EMAIL_BACKEND explicitly (and the EMAIL_HOST_* values) for real SMTP.
#   * Otherwise: in DEBUG we fall back to the console backend so OTP / reset
#     codes are printed to the terminal running the server — the previous
#     default was SMTP to localhost:587, which silently fails on a dev box and
#     made it look like "no OTP is sent". In production with no override we keep
#     SMTP so a mis-config is loud.
_default_email_backend = (
    'django.core.mail.backends.console.EmailBackend' if DEBUG
    else 'django.core.mail.backends.smtp.EmailBackend')
EMAIL_BACKEND = os.environ.get('EMAIL_BACKEND', _default_email_backend)
EMAIL_HOST = os.environ.get('EMAIL_HOST', 'localhost')
EMAIL_PORT = int(os.environ.get('EMAIL_PORT', '587'))
EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER', '')
EMAIL_HOST_PASSWORD = os.environ.get('EMAIL_HOST_PASSWORD', '')
EMAIL_USE_TLS = os.environ.get('EMAIL_USE_TLS', 'True').lower() == 'true'
EMAIL_TIMEOUT = int(os.environ.get('EMAIL_TIMEOUT', '10'))
DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', 'Featherflow <noreply@featherflow.local>')
# True when codes are only observable in the server terminal (console email
# backend and/or the console SMS stub) — surfaced to the client so the OTP
# screen can tell the user where to look.
OTP_DEV_DELIVERY = (
    EMAIL_BACKEND.endswith('console.EmailBackend')
    or EMAIL_BACKEND.endswith('locmem.EmailBackend')
    or SMS_BACKEND == 'console')

# Make our own INFO logs visible on the console. Django's default root logger
# only surfaces WARNING+, so OTP-delivery / upload / signup-cache breadcrumbs
# were being swallowed.
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'ff': {'format': '[{asctime}] {levelname} {name}: {message}', 'style': '{'},
    },
    'handlers': {
        'console': {'class': 'logging.StreamHandler', 'formatter': 'ff'},
    },
    'loggers': {
        name: {
            'handlers': ['console'],
            'level': os.environ.get('FF_LOG_LEVEL', 'INFO'),
            'propagate': False,
        }
        for name in ('verification', 'users', 'signup', 'api', 'billing')
    },
}
CONSULTATION_PLATFORM_THRESHOLD = os.environ.get('CONSULTATION_PLATFORM_THRESHOLD', '1500.00')
CONSULTATION_PLATFORM_RATE = os.environ.get('CONSULTATION_PLATFORM_RATE', '5.00')
# Video consultations open an external Jitsi Meet room (no native SDK / TURN
# server to run). Point this at a self-hosted Jitsi to keep calls private.
JITSI_BASE_URL = os.environ.get('JITSI_BASE_URL', 'https://meet.jit.si').rstrip('/')
