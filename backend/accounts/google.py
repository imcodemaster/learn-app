"""
Google Sign-In: verify the ID token the app receives from Google.

The token's signature is checked against Google's published keys, and the
audience must be one of our OAuth client IDs. No Django imports here so the
logic can be unit-tested on its own.
"""

from __future__ import annotations

from typing import Callable

import jwt
from jwt import PyJWKClient

GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = ("accounts.google.com", "https://accounts.google.com")

_jwk_client: PyJWKClient | None = None


class GoogleTokenError(Exception):
    pass


def _default_key_resolver(token: str):
    global _jwk_client
    if _jwk_client is None:
        _jwk_client = PyJWKClient(GOOGLE_JWKS_URL, cache_keys=True, lifespan=3600)
    return _jwk_client.get_signing_key_from_jwt(token).key


def verify_google_id_token(
    id_token: str,
    client_ids: list[str],
    key_resolver: Callable[[str], object] | None = None,
    leeway: int = 60,
) -> dict:
    """Returns the verified claims (sub, email, name, picture...) or raises GoogleTokenError."""
    if not client_ids:
        raise GoogleTokenError("Google sign-in is not configured (GOOGLE_CLIENT_IDS is empty).")
    if not id_token or len(id_token) > 4096:
        raise GoogleTokenError("Missing or oversized token.")
    resolver = key_resolver or _default_key_resolver
    try:
        key = resolver(id_token)
        claims = jwt.decode(
            id_token,
            key,
            algorithms=["RS256"],
            audience=client_ids,
            leeway=leeway,
            options={"require": ["exp", "iat", "iss", "aud", "sub"]},
        )
    except jwt.PyJWTError as exc:
        raise GoogleTokenError(f"Invalid Google token: {exc}") from exc

    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise GoogleTokenError("Token was not issued by Google.")
    if not isinstance(claims.get("sub"), str) or not claims["sub"]:
        raise GoogleTokenError("Token has no subject.")
    if claims.get("email") and claims.get("email_verified") not in (True, "true"):
        raise GoogleTokenError("Google email address is not verified.")
    return claims
