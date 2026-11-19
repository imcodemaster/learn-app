"""
Shared API helpers: consistent JSON envelope and error format.

Success: {"data": ..., "meta": {...}}
Error:   {"error": {"code": "...", "message": "...", "fields": {...}}}
"""

from __future__ import annotations

import logging
import math

from django.conf import settings
from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.http import Http404
from rest_framework import exceptions
from rest_framework.response import Response

from .utils import parse_int

logger = logging.getLogger("learnincreation")


class ApiError(exceptions.APIException):
    """An error whose message is safe to show to the user."""

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        fields: dict | None = None,
        extra: dict | None = None,
        headers: dict | None = None,
    ):
        super().__init__(detail=message, code=code)
        self.status_code = status_code
        self.error_code = code
        self.message = message
        self.fields = fields or {}
        self.extra = extra or {}
        self.extra_headers = headers or {}


def ok(data, status_code: int = 200, meta: dict | None = None) -> Response:
    payload = {"data": data}
    if meta is not None:
        payload["meta"] = meta
    return Response(payload, status=status_code)


def error_response(status_code, code, message, fields=None, extra=None, headers=None) -> Response:
    error = {"code": code, "message": message}
    if fields:
        error["fields"] = fields
    if extra:
        error.update(extra)
    return Response({"error": error}, status=status_code, headers=headers)


def payments_mode() -> str:
    """'mock' (simulated payments) is only possible outside production."""
    if settings.PAYMENTS_MODE == "mock" and settings.APP_ENV != "production":
        return "mock"
    return "razorpay"


def not_found(message: str = "Not found.") -> ApiError:
    return ApiError(404, "not_found", message)


def field_error(field: str, message: str, code: str = "validation_error") -> ApiError:
    return ApiError(422, code, message, fields={field: message})


def _first_message(value) -> str:
    if isinstance(value, (list, tuple)):
        return _first_message(value[0]) if value else "Invalid value."
    if isinstance(value, dict):
        for item in value.values():
            return _first_message(item)
        return "Invalid value."
    return str(value)


def exception_handler(exc, context):
    if isinstance(exc, ApiError):
        return error_response(exc.status_code, exc.error_code, exc.message, exc.fields, exc.extra, exc.extra_headers)

    if isinstance(exc, exceptions.ValidationError):
        detail = exc.detail
        if isinstance(detail, dict):
            fields = {str(key): _first_message(value) for key, value in detail.items()}
            message = fields.pop("non_field_errors", None) or "Please check the highlighted fields."
            return error_response(422, "validation_error", message, fields or None)
        return error_response(422, "validation_error", _first_message(detail))

    if isinstance(exc, (exceptions.NotAuthenticated, exceptions.AuthenticationFailed)):
        request = context.get("request")
        expired = bool(getattr(getattr(request, "_request", None), "li_token_rejected", False))
        if expired:
            return error_response(401, "session_expired", "Your session has expired. Please sign in again.",
                                  headers={"WWW-Authenticate": "Bearer"})
        return error_response(401, "unauthenticated", "Please sign in to continue.", headers={"WWW-Authenticate": "Bearer"})

    if isinstance(exc, (exceptions.PermissionDenied, DjangoPermissionDenied)):
        return error_response(403, "forbidden", "You do not have access to this.")

    if isinstance(exc, (exceptions.NotFound, Http404)):
        return error_response(404, "not_found", "Not found.")

    if isinstance(exc, exceptions.Throttled):
        wait = max(1, math.ceil(exc.wait or 60))
        return error_response(429, "rate_limited", "Too many requests. Please slow down and try again.",
                              extra={"retry_after": wait}, headers={"Retry-After": str(wait)})

    if isinstance(exc, exceptions.MethodNotAllowed):
        return error_response(405, "method_not_allowed", "Method not allowed.")

    if isinstance(exc, exceptions.ParseError):
        return error_response(400, "invalid_json", "The request body must be valid JSON.")

    if isinstance(exc, exceptions.UnsupportedMediaType):
        return error_response(415, "unsupported_media_type", "Send JSON with Content-Type: application/json.")

    if isinstance(exc, exceptions.APIException):
        return error_response(exc.status_code, "error", _first_message(exc.detail))

    logger.exception("Unhandled API error", exc_info=exc)
    if settings.DEBUG:
        return None  # show Django's debug page while developing
    return error_response(500, "server_error", "Something went wrong. Please try again.")


def paginate(request, queryset, default_per_page: int = 20, max_per_page: int = 50):
    page = parse_int(request.query_params.get("page"), 1, 1, 100_000)
    per_page = parse_int(request.query_params.get("per_page"), default_per_page, 1, max_per_page)
    total = queryset.count()
    start = (page - 1) * per_page
    items = list(queryset[start:start + per_page])
    meta = {
        "page": page,
        "per_page": per_page,
        "total": total,
        "total_pages": max(1, math.ceil(total / per_page)),
    }
    return items, meta


def absolute_url(request, path_or_url: str) -> str:
    if not path_or_url:
        return ""
    if path_or_url.startswith("http://") or path_or_url.startswith("https://"):
        return path_or_url
    if settings.PUBLIC_BASE_URL:
        return settings.PUBLIC_BASE_URL + "/" + path_or_url.lstrip("/")
    return request.build_absolute_uri(path_or_url)


def base_url(request) -> str:
    return settings.PUBLIC_BASE_URL or request.build_absolute_uri("/").rstrip("/")
