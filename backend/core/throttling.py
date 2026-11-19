"""API request throttles that identify visitors by their real IP (see core.ratelimit.client_ip)."""

from rest_framework.throttling import AnonRateThrottle, UserRateThrottle

from .ratelimit import client_ip


class _ClientIpMixin:
    def get_ident(self, request):
        return client_ip(request)


class AnonThrottle(_ClientIpMixin, AnonRateThrottle):
    """Requests from signed-out visitors, counted per visitor IP."""


class UserThrottle(_ClientIpMixin, UserRateThrottle):
    """Requests from signed-in users, counted per account (per IP when signed out)."""
