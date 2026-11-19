from django.contrib import admin
from django.http import HttpResponse, JsonResponse
from django.utils import timezone
from django.views import defaults
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny

from . import ratelimit
from .api import ApiError, ok, payments_mode
from .models import Faq, SiteSettings
from .utils import iso_utc


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request):
    return ok({"status": "ok", "time": iso_utc(timezone.now())})


@api_view(["GET"])
@permission_classes([AllowAny])
def app_info(request):
    from django.conf import settings

    site = SiteSettings.load()
    mode = payments_mode()
    return ok({
        "org_name": site.org_name,
        "tagline": site.tagline,
        "hero_title": site.hero_title,
        "about": site.about,
        "phone": site.phone,
        "email": site.email,
        "address": site.address,
        "hours": site.hours,
        "website": site.website,
        "social": {
            "youtube": site.youtube_url,
            "instagram": site.instagram_url,
            "linkedin": site.linkedin_url,
        },
        "privacy_url": site.privacy_url,
        "terms_url": site.terms_url,
        "faq": [{"q": f.question, "a": f.answer} for f in Faq.objects.filter(is_active=True)],
        "payments": {"mode": mode, "key_id": settings.RAZORPAY_KEY_ID if mode == "razorpay" else ""},
        "auth": {"google_enabled": bool(settings.GOOGLE_CLIENT_IDS), "phone_enabled": True},
    })


def throttled_admin_login(request, *args, **kwargs):
    """Admin login with brute-force protection (per IP and per username)."""
    if request.method == "POST":
        ip = ratelimit.client_ip(request)
        username = (request.POST.get("username") or "").strip().lower()[:190]
        try:
            ratelimit.hit(f"admin-login:ip:{ip}", 10, 900)
            if username:
                ratelimit.hit(f"admin-login:user:{username}", 5, 900)
        except ApiError:
            return HttpResponse(
                "Too many login attempts. Please wait 15 minutes and try again.",
                status=429,
                content_type="text/plain; charset=utf-8",
            )
    return admin.site.login(request)


def not_found(request, exception=None):
    if request.path.startswith("/api/"):
        return JsonResponse({"error": {"code": "not_found", "message": "Endpoint not found."}}, status=404)
    return defaults.page_not_found(request, exception)


def server_error(request):
    if request.path.startswith("/api/"):
        return JsonResponse(
            {"error": {"code": "server_error", "message": "Something went wrong. Please try again."}}, status=500
        )
    return defaults.server_error(request)
