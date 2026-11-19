"""
Minimal Razorpay client: create orders and verify signatures.
No Django imports, so it can be unit-tested on its own.

Security notes
- The amount always comes from our database, never from the app.
- A payment only counts after its HMAC-SHA256 signature checks out with our
  secret key (or a signed webhook arrives), so a tampered app cannot fake one.
"""

from __future__ import annotations

import hashlib
import hmac

import requests


class RazorpayError(Exception):
    pass


class RazorpayClient:
    API_BASE = "https://api.razorpay.com/v1"

    def __init__(self, key_id: str, key_secret: str, webhook_secret: str = "", session=None, timeout: int = 20):
        self.key_id = key_id or ""
        self.key_secret = key_secret or ""
        self.webhook_secret = webhook_secret or ""
        self.session = session or requests
        self.timeout = timeout

    @property
    def configured(self) -> bool:
        return bool(self.key_id and self.key_secret)

    def create_order(self, amount_paise: int, currency: str, receipt: str, notes: dict) -> dict:
        payload = {
            "amount": int(amount_paise),
            "currency": currency,
            "receipt": receipt[:40],
            "notes": {str(k)[:40]: str(v)[:250] for k, v in list(notes.items())[:15]},
        }
        try:
            response = self.session.post(
                f"{self.API_BASE}/orders",
                auth=(self.key_id, self.key_secret),
                json=payload,
                timeout=self.timeout,
            )
        except requests.RequestException as exc:
            raise RazorpayError(f"Network error talking to Razorpay: {exc}") from exc
        try:
            data = response.json()
        except ValueError:
            data = {}
        if response.status_code != 200 or not isinstance(data, dict) or not isinstance(data.get("id"), str):
            raise RazorpayError(f"Order creation failed (HTTP {response.status_code}): {str(data)[:300]}")
        if int(data.get("amount", -1)) != int(amount_paise):
            raise RazorpayError("Razorpay returned a different amount than requested.")
        return data

    def verify_payment_signature(self, order_id: str, payment_id: str, signature: str) -> bool:
        if not self.key_secret or not order_id or not payment_id or not signature:
            return False
        expected = hmac.new(
            self.key_secret.encode("utf-8"), f"{order_id}|{payment_id}".encode("utf-8"), hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(expected, signature.strip().lower())

    def verify_webhook_signature(self, body: bytes, signature: str) -> bool:
        if not self.webhook_secret or not signature:
            return False
        expected = hmac.new(self.webhook_secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature.strip().lower())
