"""
Small pure-Python helpers (no Django imports, so they can be unit-tested on
their own).
"""

from __future__ import annotations

import calendar
import hashlib
import hmac
import ipaddress
import re
import secrets
from datetime import date, datetime, time, timezone
from decimal import ROUND_HALF_UP, Decimal

_PHONE_DIGITS = re.compile(r"\D+")
_INDIAN_MOBILE = re.compile(r"^[6-9]\d{9}$")
_TOKEN_RE = re.compile(r"^li_[A-Za-z0-9_\-]{20,100}$")
_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # no look-alike characters


def normalize_indian_phone(raw: str) -> str | None:
    """'98765 43210', '09876543210', '+91 9876543210' → '+919876543210'."""
    digits = _PHONE_DIGITS.sub("", raw or "")
    if len(digits) == 12 and digits.startswith("91"):
        digits = digits[2:]
    elif len(digits) == 11 and digits.startswith("0"):
        digits = digits[1:]
    if not _INDIAN_MOBILE.match(digits):
        return None
    return "+91" + digits


def seat_label(seat_no: int, per_row: int) -> str:
    """Seat 1 with 5 seats per row → 'A1'; seat 7 → 'B2'; row 27 → 'AA'."""
    per_row = max(1, per_row)
    row, col = divmod(seat_no - 1, per_row)
    letters = ""
    n = row
    while True:
        letters = chr(65 + n % 26) + letters
        n = n // 26 - 1
        if n < 0:
            break
    return f"{letters}{col + 1}"


def add_months(start: date, months: int) -> date:
    """Adds whole months, clamping the day for short months (31 Jan + 1 → 28/29 Feb)."""
    index = start.month - 1 + months
    year = start.year + index // 12
    month = index % 12 + 1
    day = min(start.day, calendar.monthrange(year, month)[1])
    return date(year, month, day)


def times_overlap(a_start: time, a_end: time, b_start: time, b_end: time) -> bool:
    """True when two same-day time ranges [start, end) overlap."""
    return a_start < b_end and b_start < a_end


def periods_overlap(a_start: date, a_end: date, b_start: date, b_end: date) -> bool:
    """True when two date ranges [start, end) overlap (end date exclusive)."""
    return a_start < b_end and b_start < a_end


def new_token() -> str:
    """Session token sent to the app: 'li_' + 256 random bits."""
    return "li_" + secrets.token_urlsafe(32)


def is_token_format(value: str) -> bool:
    return bool(_TOKEN_RE.match(value or ""))


def hash_token(token: str) -> str:
    """Only this hash is stored, so a database leak does not leak sessions."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def random_code(length: int) -> str:
    return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(length))


def new_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def otp_hash(secret: str, purpose: str, destination: str, code: str) -> str:
    message = f"{purpose}|{destination}|{code}".encode("utf-8")
    return hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()


def reading_minutes(text: str) -> int:
    words = len((text or "").split())
    return max(1, -(-words // 200))


def lines(text: str | None) -> list[str]:
    return [line.strip() for line in (text or "").splitlines() if line.strip()]


def to_paise(amount: Decimal | int | float | str) -> int:
    """Rupees (Decimal) → integer paise, rounding half up."""
    value = (Decimal(str(amount)) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    return int(value)


def format_rupees(paise: int) -> str:
    rupees = Decimal(paise) / 100
    if rupees == rupees.to_integral_value():
        return f"₹{int(rupees):,}"
    return f"₹{rupees:,.2f}"


def iso_utc(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def hhmm(value: time | None) -> str | None:
    return value.strftime("%H:%M") if value is not None else None


def parse_int(value: object, default: int, minimum: int, maximum: int) -> int:
    try:
        number = int(str(value))
    except (TypeError, ValueError):
        return default
    return max(minimum, min(maximum, number))


def valid_ip_or_none(value: str) -> str | None:
    try:
        return str(ipaddress.ip_address((value or "").strip()))
    except ValueError:
        return None


def client_ip_from(remote_addr: str, forwarded_for: str, num_proxies: int) -> str:
    """
    Picks the client IP. X-Forwarded-For is only trusted when the server is
    known to sit behind `num_proxies` proxies (otherwise it can be spoofed).
    """
    if num_proxies > 0 and forwarded_for:
        hops = [hop.strip() for hop in forwarded_for.split(",") if hop.strip()]
        if len(hops) >= num_proxies:
            candidate = valid_ip_or_none(hops[-num_proxies])
            if candidate:
                return candidate
    return valid_ip_or_none(remote_addr) or "0.0.0.0"


_MEDIA_LINK = re.compile(r"\]\((/media/[^)\s]+)")


def absolutize_media_links(markdown: str, base_url: str) -> str:
    """Turns ](/media/x.png) into ](https://host/media/x.png) so the app can load images."""
    base = base_url.rstrip("/")
    return _MEDIA_LINK.sub(lambda m: "](" + base + m.group(1), markdown or "")
