from datetime import timedelta

from django.conf import settings
from django.utils import timezone
from rest_framework.authentication import BaseAuthentication, get_authorization_header

from core.utils import hash_token, is_token_format

from .models import AuthToken


class BearerTokenAuthentication(BaseAuthentication):
    """
    `Authorization: Bearer li_...` from the mobile app.

    A bad or expired token is treated as "not signed in" so that public
    endpoints keep working; endpoints that need a user then answer
    401 session_expired and the app asks the student to sign in again.
    """

    def authenticate(self, request):
        parts = get_authorization_header(request).split()
        if not parts or parts[0].lower() != b"bearer":
            return None
        if len(parts) != 2:
            return self._reject(request)
        try:
            token = parts[1].decode("ascii")
        except UnicodeDecodeError:
            return self._reject(request)
        if not is_token_format(token):
            return self._reject(request)

        now = timezone.now()
        auth_token = (
            AuthToken.objects.select_related("user")
            .filter(token_hash=hash_token(token), expires_at__gt=now)
            .first()
        )
        if auth_token is None or not auth_token.user.is_active or auth_token.user.deleted_at is not None:
            return self._reject(request)

        # Sliding expiry; write at most once every 5 minutes.
        if (now - auth_token.last_used_at).total_seconds() > 300:
            updates = {"last_used_at": now}
            days = settings.APP_SESSION_DAYS
            if (auth_token.expires_at - now).total_seconds() < days * 86400 / 2:
                updates["expires_at"] = now + timedelta(days=days)
            AuthToken.objects.filter(pk=auth_token.pk).update(**updates)
        return (auth_token.user, auth_token)

    @staticmethod
    def _reject(request):
        raw = getattr(request, "_request", request)
        raw.li_token_rejected = True
        return None

    def authenticate_header(self, request):
        return "Bearer"
