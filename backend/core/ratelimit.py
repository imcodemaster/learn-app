"""Per-key rate limits (per phone number, per email, per IP...)."""

from __future__ import annotations

import hashlib
import time

from django.conf import settings
from django.core.cache import cache

from .api import ApiError
from .utils import client_ip_from


def client_ip(request) -> str:
    meta = request.META
    return client_ip_from(meta.get("REMOTE_ADDR", ""), meta.get("HTTP_X_FORWARDED_FOR", ""), settings.NUM_PROXIES)


def hit(key: str, limit: int, window_seconds: int,
        message: str = "Too many attempts. Please wait a moment and try again.") -> None:
    """Counts one attempt for `key`; raises a 429 ApiError once `limit` is exceeded."""
    now = int(time.time())
    window_start = now - (now % window_seconds)
    bucket = "rl:" + hashlib.sha256(key.encode("utf-8")).hexdigest() + f":{window_start}"
    if cache.add(bucket, 1, timeout=window_seconds + 5):
        count = 1
    else:
        try:
            count = cache.incr(bucket)
        except ValueError:  # expired between add() and incr()
            cache.add(bucket, 1, timeout=window_seconds + 5)
            count = 1
    if count > limit:
        retry_after = max(1, window_start + window_seconds - now)
        raise ApiError(429, "rate_limited", message, extra={"retry_after": retry_after},
                       headers={"Retry-After": str(retry_after)})
