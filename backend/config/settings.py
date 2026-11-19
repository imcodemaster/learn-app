"""
Django settings for the LearnInCreation backend.

Every deployment-specific value comes from environment variables. For local
development, copy `.env.example` to `.env` and edit it; the file is read
automatically at startup.
"""

import os
import sys
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent


def _load_env_file(path: Path) -> None:
    """Minimal .env reader (KEY=value lines). Real environment variables win."""
    if not path.is_file():
        return
    # utf-8-sig: Windows editors sometimes save a byte-order mark at the start.
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        os.environ.setdefault(key, value)


_load_env_file(BASE_DIR / ".env")


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def env_bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


def env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        return default


def env_list(name: str, default: str = "") -> list[str]:
    return [item.strip() for item in os.environ.get(name, default).split(",") if item.strip()]


TESTING = len(sys.argv) > 1 and sys.argv[1] == "test"

# --------------------------------------------------------------------------
# Core
# --------------------------------------------------------------------------
DEBUG = env_bool("DJANGO_DEBUG", False)
APP_ENV = env("APP_ENV", "production").lower()  # "local" or "production"

SECRET_KEY = env("DJANGO_SECRET_KEY")
if not SECRET_KEY:
    if DEBUG or TESTING:
        SECRET_KEY = "insecure-development-key-do-not-use-in-production-0123456789"
    else:
        raise ImproperlyConfigured("Set the DJANGO_SECRET_KEY environment variable (a long random string).")
if APP_ENV == "production" and not TESTING and len(SECRET_KEY) < 40:
    raise ImproperlyConfigured("DJANGO_SECRET_KEY must be at least 40 characters long in production.")

ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1,10.0.2.2")
CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")

# Render gives each service an address such as learnincreation-api.onrender.com
# and passes it in RENDER_EXTERNAL_HOSTNAME; accept it next to your own domain.
RENDER_EXTERNAL_HOSTNAME = env("RENDER_EXTERNAL_HOSTNAME").strip()
if RENDER_EXTERNAL_HOSTNAME and RENDER_EXTERNAL_HOSTNAME not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append(RENDER_EXTERNAL_HOSTNAME)
    CSRF_TRUSTED_ORIGINS.append(f"https://{RENDER_EXTERNAL_HOSTNAME}")

# Public base URL of this server, e.g. https://api.learnincreation.com.
# Used to build absolute links to uploaded images. Optional: when empty the
# request's own host is used.
PUBLIC_BASE_URL = env("PUBLIC_BASE_URL").rstrip("/")

# Hard-to-guess admin path cuts down on bots probing /admin/.
ADMIN_URL = env("ADMIN_URL", "admin/").strip("/") + "/"

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "core",
    "accounts",
    "courses",
    "payments",
    "studycenter",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "core.middleware.SecurityHeadersMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

# --------------------------------------------------------------------------
# Database (PostgreSQL recommended; MySQL and SQLite also supported)
# --------------------------------------------------------------------------
DB_ENGINE = env("DB_ENGINE", "sqlite").lower()
# A hosting service's DATABASE_URL (postgres://user:password@host:port/name)
# takes priority over the separate DB_* settings below.
DATABASE_URL = env("DATABASE_URL").strip()
if DATABASE_URL:
    from config.dburl import database_from_url

    try:
        DATABASES = {"default": database_from_url(DATABASE_URL)}
    except ValueError as exc:
        raise ImproperlyConfigured(str(exc)) from exc
    DB_ENGINE = "mysql" if DATABASES["default"]["ENGINE"].endswith("mysql") else "postgres"
elif DB_ENGINE in ("postgres", "postgresql"):
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": env("DB_NAME", "learnincreation"),
            "USER": env("DB_USER", "learnincreation"),
            "PASSWORD": env("DB_PASSWORD"),
            "HOST": env("DB_HOST", "localhost"),
            "PORT": env("DB_PORT", "5432"),
            "CONN_MAX_AGE": 60,
        }
    }
elif DB_ENGINE == "mysql":
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.mysql",
            "NAME": env("DB_NAME", "learnincreation"),
            "USER": env("DB_USER", "learnincreation"),
            "PASSWORD": env("DB_PASSWORD"),
            "HOST": env("DB_HOST", "localhost"),
            "PORT": env("DB_PORT", "3306"),
            "CONN_MAX_AGE": 60,
            "OPTIONS": {"charset": "utf8mb4", "init_command": "SET sql_mode='STRICT_TRANS_TABLES'"},
        }
    }
elif DB_ENGINE == "sqlite":
    DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "db.sqlite3"}}
else:
    raise ImproperlyConfigured("DB_ENGINE must be postgres, mysql or sqlite.")

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTH_USER_MODEL = "accounts.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 8}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# --------------------------------------------------------------------------
# Cache (used for rate limiting). Default: in-process memory.
# Set CACHE_URL=redis://host:6379/0 or CACHE_URL=db (then run createcachetable)
# when you run several server processes.
# --------------------------------------------------------------------------
CACHE_URL = env("CACHE_URL")
if CACHE_URL.startswith("redis://") or CACHE_URL.startswith("rediss://"):
    CACHES = {"default": {"BACKEND": "django.core.cache.backends.redis.RedisCache", "LOCATION": CACHE_URL}}
elif CACHE_URL == "db":
    CACHES = {"default": {"BACKEND": "django.core.cache.backends.db.DatabaseCache", "LOCATION": "django_cache"}}
else:
    CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache", "LOCATION": "learnincreation"}}

# --------------------------------------------------------------------------
# Internationalisation
# --------------------------------------------------------------------------
LANGUAGE_CODE = "en-us"
TIME_ZONE = "Asia/Kolkata"
USE_I18N = True
USE_TZ = True

# --------------------------------------------------------------------------
# Static & uploaded files
# --------------------------------------------------------------------------
STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "/media/"
MEDIA_ROOT = Path(env("MEDIA_ROOT", str(BASE_DIR / "media")))
# Let Django serve uploaded images itself (fine for small sites). Turn off when
# Nginx or a CDN serves /media/.
SERVE_MEDIA = env_bool("SERVE_MEDIA", True)

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"
        if (DEBUG or TESTING)
        else "whitenoise.storage.CompressedStaticFilesStorage"
    },
}

DATA_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024
FILE_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024
DATA_UPLOAD_MAX_NUMBER_FIELDS = 5000
MAX_IMAGE_UPLOAD_BYTES = 4 * 1024 * 1024

# --------------------------------------------------------------------------
# Django REST Framework (the mobile app API)
# --------------------------------------------------------------------------
NUM_PROXIES = env_int("NUM_PROXIES", 0)  # set to 1 behind Nginx / a load balancer
# Header in which a trusted proxy passes the visitor's real IP, e.g. True-Client-IP
# on Render (its Cloudflare edge sets it) or CF-Connecting-IP behind Cloudflare.
# Only set this when every request reaches the server through that proxy.
_client_ip_header = env("CLIENT_IP_HEADER").strip()
CLIENT_IP_HEADER = ("HTTP_" + _client_ip_header.upper().replace("-", "_")) if _client_ip_header else ""

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": ["accounts.authentication.BearerTokenAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.AllowAny"],
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser"],
    "EXCEPTION_HANDLER": "core.api.exception_handler",
    "DEFAULT_THROTTLE_CLASSES": [
        "core.throttling.AnonThrottle",
        "core.throttling.UserThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {"anon": "120/min", "user": "300/min"},
    "NUM_PROXIES": NUM_PROXIES,
    "UNAUTHENTICATED_USER": "django.contrib.auth.models.AnonymousUser",
}

# --------------------------------------------------------------------------
# Security
# --------------------------------------------------------------------------
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
SECURE_CROSS_ORIGIN_OPENER_POLICY = "same-origin"
X_FRAME_OPTIONS = "DENY"
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
SESSION_COOKIE_AGE = 60 * 60 * 12  # admin panel sessions: 12 hours
CSRF_COOKIE_SAMESITE = "Lax"

if env_bool("DJANGO_BEHIND_PROXY", False):
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

if not DEBUG:
    SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", True) and not TESTING
    # Hosting health checks call this over plain http from inside their network.
    SECURE_REDIRECT_EXEMPT = [r"^api/health$"]
    SESSION_COOKIE_SECURE = not TESTING
    CSRF_COOKIE_SECURE = not TESTING
    SECURE_HSTS_SECONDS = env_int("DJANGO_HSTS_SECONDS", 31536000)
    SECURE_HSTS_INCLUDE_SUBDOMAINS = False
    SECURE_HSTS_PRELOAD = False

# --------------------------------------------------------------------------
# Email (password-reset codes)
# --------------------------------------------------------------------------
EMAIL_BACKEND = env(
    "EMAIL_BACKEND",
    "django.core.mail.backends.console.EmailBackend" if (DEBUG or APP_ENV != "production") else "django.core.mail.backends.smtp.EmailBackend",
)
EMAIL_HOST = env("EMAIL_HOST", "smtp.gmail.com")
EMAIL_PORT = env_int("EMAIL_PORT", 587)
EMAIL_HOST_USER = env("EMAIL_HOST_USER")
EMAIL_HOST_PASSWORD = env("EMAIL_HOST_PASSWORD")
EMAIL_USE_TLS = env_bool("EMAIL_USE_TLS", True)
EMAIL_USE_SSL = env_bool("EMAIL_USE_SSL", False)
EMAIL_TIMEOUT = 15
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL", "LearnInCreation <no-reply@learnincreation.com>")

# --------------------------------------------------------------------------
# LearnInCreation app settings
# --------------------------------------------------------------------------
APP_SESSION_DAYS = env_int("APP_SESSION_DAYS", 30)

OTP_TTL_SECONDS = env_int("OTP_TTL_SECONDS", 300)
OTP_EMAIL_TTL_SECONDS = env_int("OTP_EMAIL_TTL_SECONDS", 900)
OTP_RESEND_SECONDS = env_int("OTP_RESEND_SECONDS", 60)
OTP_MAX_ATTEMPTS = env_int("OTP_MAX_ATTEMPTS", 5)

# console (prints codes to the server log) | msg91 | fast2sms | twilio
SMS_BACKEND = env("SMS_BACKEND", "console").lower()
MSG91_AUTH_KEY = env("MSG91_AUTH_KEY")
MSG91_TEMPLATE_ID = env("MSG91_TEMPLATE_ID")
FAST2SMS_API_KEY = env("FAST2SMS_API_KEY")
TWILIO_ACCOUNT_SID = env("TWILIO_ACCOUNT_SID")
TWILIO_AUTH_TOKEN = env("TWILIO_AUTH_TOKEN")
TWILIO_FROM = env("TWILIO_FROM")

# OAuth client IDs whose Google ID tokens are accepted (the *Web* client ID that
# the app passes as serverClientId). Comma separated.
GOOGLE_CLIENT_IDS = env_list("GOOGLE_CLIENT_IDS")

# razorpay | mock  (mock = simulated payments for testing; refused when APP_ENV=production)
PAYMENTS_MODE = env("PAYMENTS_MODE", "razorpay").lower()
RAZORPAY_KEY_ID = env("RAZORPAY_KEY_ID")
RAZORPAY_KEY_SECRET = env("RAZORPAY_KEY_SECRET")
RAZORPAY_WEBHOOK_SECRET = env("RAZORPAY_WEBHOOK_SECRET")

BOOKING_HOLD_MINUTES = env_int("BOOKING_HOLD_MINUTES", 10)

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "[%(asctime)s] %(levelname)s %(name)s: %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain"}},
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        "django.security": {"handlers": ["console"], "level": "WARNING", "propagate": False},
        "learnincreation": {"handlers": ["console"], "level": "INFO", "propagate": False},
    },
}
