"""
One-time codes for mobile login (SMS) and password reset (email).
Codes are stored as HMAC hashes, expire, allow limited wrong attempts and can
be used only once.
"""

import hmac
import re
from datetime import timedelta

from django.conf import settings
from django.db.models import F
from django.utils import timezone

from core.api import ApiError
from core.utils import new_otp, otp_hash

from .models import OtpCode

INVALID_CODE = "The code is incorrect or has expired."
_SIX_DIGITS = re.compile(r"[0-9]{6}")


def _hash(purpose: str, destination: str, code: str) -> str:
    return otp_hash(settings.SECRET_KEY, purpose, destination, code)


def _invalid() -> ApiError:
    return ApiError(422, "invalid_code", INVALID_CODE, fields={"code": INVALID_CODE})


def issue(purpose: str, destination: str, ttl_seconds: int, ip: str | None) -> str:
    """Creates a fresh code (older unused ones stop working). Returns the plain code."""
    now = timezone.now()
    last = OtpCode.objects.filter(purpose=purpose, destination=destination).order_by("-created_at", "-id").first()
    cooldown = settings.OTP_RESEND_SECONDS
    if last is not None:
        elapsed = (now - last.created_at).total_seconds()
        if elapsed < cooldown:
            wait = int(cooldown - elapsed) + 1
            raise ApiError(429, "rate_limited", "Please wait a little before requesting another code.",
                           extra={"retry_after": wait}, headers={"Retry-After": str(wait)})
    OtpCode.objects.filter(purpose=purpose, destination=destination, consumed_at__isnull=True).update(consumed_at=now)
    code = new_otp()
    OtpCode.objects.create(
        purpose=purpose,
        destination=destination,
        code_hash=_hash(purpose, destination, code),
        expires_at=now + timedelta(seconds=ttl_seconds),
        ip=ip,
        created_at=now,
    )
    return code


def discard(purpose: str, destination: str) -> None:
    """Removes unused codes, e.g. when the SMS could not be sent."""
    OtpCode.objects.filter(purpose=purpose, destination=destination, consumed_at__isnull=True).delete()


def verify(purpose: str, destination: str, code: str) -> None:
    """Raises ApiError when the code is wrong, expired, already used or tried too often."""
    now = timezone.now()
    row = (
        OtpCode.objects.filter(purpose=purpose, destination=destination, consumed_at__isnull=True)
        .order_by("-created_at", "-id")
        .first()
    )
    if row is None or row.expires_at <= now:
        raise _invalid()
    if row.attempts >= settings.OTP_MAX_ATTEMPTS:
        raise ApiError(429, "too_many_attempts", "Too many wrong attempts. Please request a new code.")
    if not _SIX_DIGITS.fullmatch(code or "") or not hmac.compare_digest(row.code_hash, _hash(purpose, destination, code)):
        OtpCode.objects.filter(pk=row.pk).update(attempts=F("attempts") + 1)
        raise _invalid()
    # Atomic single use: two simultaneous requests cannot both succeed.
    used = OtpCode.objects.filter(pk=row.pk, consumed_at__isnull=True).update(consumed_at=now)
    if used != 1:
        raise _invalid()
