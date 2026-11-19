"""
Tests for the Django-independent building blocks (run with plain unittest or
with `python manage.py test`).
"""

import hashlib
import hmac
import io
import json
import time
import unittest
from datetime import date, time as dtime

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from PIL import Image

from accounts.google import GoogleTokenError, verify_google_id_token
from config.dburl import database_from_url
from accounts.sms_providers import SmsError, send_fast2sms, send_msg91, send_twilio
from core.images import ImageRejected, sanitize_image_bytes
from core.utils import (
    absolutize_media_links,
    add_months,
    client_ip_from,
    format_rupees,
    hash_token,
    is_token_format,
    new_otp,
    new_token,
    normalize_indian_phone,
    otp_hash,
    periods_overlap,
    seat_label,
    times_overlap,
    to_paise,
)
from payments.razorpay import RazorpayClient, RazorpayError


class FakeResponse:
    def __init__(self, status_code=200, payload=None):
        self.status_code = status_code
        self._payload = payload

    def json(self):
        if self._payload is None:
            raise ValueError("no json")
        return self._payload


class FakeSession:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def post(self, url, **kwargs):
        self.calls.append((url, kwargs))
        return self.response


class UtilsTests(unittest.TestCase):
    def test_phone_normalisation(self):
        self.assertEqual(normalize_indian_phone("9876543210"), "+919876543210")
        self.assertEqual(normalize_indian_phone("+91 98765 43210"), "+919876543210")
        self.assertEqual(normalize_indian_phone("09876543210"), "+919876543210")
        self.assertEqual(normalize_indian_phone("919876543210"), "+919876543210")
        self.assertIsNone(normalize_indian_phone("12345"))
        self.assertIsNone(normalize_indian_phone("5876543210"))  # Indian mobiles start 6-9
        self.assertIsNone(normalize_indian_phone("' OR 1=1 --"))

    def test_seat_labels(self):
        self.assertEqual(seat_label(1, 5), "A1")
        self.assertEqual(seat_label(5, 5), "A5")
        self.assertEqual(seat_label(6, 5), "B1")
        self.assertEqual(seat_label(26 * 5 + 1, 5), "AA1")

    def test_add_months_clamps_short_months(self):
        self.assertEqual(add_months(date(2026, 1, 31), 1), date(2026, 2, 28))
        self.assertEqual(add_months(date(2028, 1, 31), 1), date(2028, 2, 29))
        self.assertEqual(add_months(date(2026, 12, 15), 1), date(2027, 1, 15))
        self.assertEqual(add_months(date(2026, 3, 1), 12), date(2027, 3, 1))

    def test_overlaps(self):
        morning, evening = (dtime(10), dtime(14)), (dtime(14), dtime(18))
        full_day = (dtime(10), dtime(18))
        self.assertFalse(times_overlap(*morning, *evening))  # back-to-back shifts don't clash
        self.assertTrue(times_overlap(*morning, *full_day))
        self.assertTrue(times_overlap(*evening, *full_day))
        self.assertFalse(periods_overlap(date(2026, 1, 1), date(2026, 2, 1), date(2026, 2, 1), date(2026, 3, 1)))
        self.assertTrue(periods_overlap(date(2026, 1, 1), date(2026, 2, 1), date(2026, 1, 31), date(2026, 3, 1)))

    def test_tokens_and_otps(self):
        token = new_token()
        self.assertTrue(is_token_format(token))
        self.assertFalse(is_token_format("li_short"))
        self.assertFalse(is_token_format("Bearer x' OR '1'='1"))
        self.assertEqual(len(hash_token(token)), 64)
        self.assertNotEqual(hash_token(token), hash_token(new_token()))
        code = new_otp()
        self.assertRegex(code, r"^\d{6}$")
        self.assertEqual(otp_hash("k", "login", "+91", code), otp_hash("k", "login", "+91", code))
        self.assertNotEqual(otp_hash("k", "login", "+91", code), otp_hash("k", "reset_password", "+91", code))

    def test_money(self):
        self.assertEqual(to_paise("499"), 49900)
        self.assertEqual(to_paise("499.99"), 49999)
        self.assertEqual(format_rupees(49900), "₹499")
        self.assertEqual(format_rupees(250000), "₹2,500")
        self.assertEqual(format_rupees(49950), "₹499.50")

    def test_client_ip(self):
        self.assertEqual(client_ip_from("10.0.0.5", "1.2.3.4", 0), "10.0.0.5")  # XFF ignored without proxies
        self.assertEqual(client_ip_from("10.0.0.5", "6.6.6.6, 1.2.3.4", 1), "1.2.3.4")  # spoofed left entry ignored
        self.assertEqual(client_ip_from("garbage", "", 0), "0.0.0.0")

    def test_media_links_become_absolute(self):
        text = "![chart](/media/courses/lessons/a.png) and [site](https://x.com)"
        self.assertEqual(
            absolutize_media_links(text, "https://api.example.com/"),
            "![chart](https://api.example.com/media/courses/lessons/a.png) and [site](https://x.com)",
        )


class ImageTests(unittest.TestCase):
    def _png(self, size=(40, 30), mode="RGB"):
        buf = io.BytesIO()
        Image.new(mode, size, "red").save(buf, format="PNG")
        return buf.getvalue()

    def test_valid_image_is_reencoded(self):
        data, ext = sanitize_image_bytes(self._png())
        self.assertEqual(ext, "png")
        with Image.open(io.BytesIO(data)) as img:
            self.assertEqual(img.size, (40, 30))

    def test_large_image_is_resized(self):
        data, _ = sanitize_image_bytes(self._png((3000, 1500)), max_side=1600)
        with Image.open(io.BytesIO(data)) as img:
            self.assertEqual(img.size, (1600, 800))

    def test_exif_is_removed(self):
        img = Image.new("RGB", (20, 20), "blue")
        exif = Image.Exif()
        exif[0x010F] = "SecretCameraMaker"
        buf = io.BytesIO()
        img.save(buf, format="JPEG", exif=exif)
        self.assertIn(b"SecretCameraMaker", buf.getvalue())
        clean, ext = sanitize_image_bytes(buf.getvalue())
        self.assertEqual(ext, "jpg")
        self.assertNotIn(b"SecretCameraMaker", clean)

    def test_non_images_and_payloads_are_rejected(self):
        with self.assertRaises(ImageRejected):
            sanitize_image_bytes(b"<?php system($_GET['c']); ?>")
        with self.assertRaises(ImageRejected):
            sanitize_image_bytes(self._png((4001, 4001), mode="L"))
        # A PHP payload appended after a real image is dropped by re-encoding.
        polyglot = self._png() + b"<?php echo 'pwned'; ?>"
        clean, _ = sanitize_image_bytes(polyglot)
        self.assertNotIn(b"<?php", clean)


class GoogleTokenTests(unittest.TestCase):
    CLIENT_ID = "web-client.apps.googleusercontent.com"

    @classmethod
    def setUpClass(cls):
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    def _token(self, key=None, **overrides):
        now = int(time.time())
        claims = {
            "iss": "https://accounts.google.com",
            "aud": self.CLIENT_ID,
            "sub": "1234567890",
            "email": "student@gmail.com",
            "email_verified": True,
            "name": "Asha Student",
            "iat": now,
            "exp": now + 3600,
        }
        claims.update(overrides)
        return jwt.encode(claims, key or self.key, algorithm="RS256", headers={"kid": "test"})

    def _verify(self, token):
        return verify_google_id_token(token, [self.CLIENT_ID], key_resolver=lambda _t: self.key.public_key())

    def test_valid_token(self):
        claims = self._verify(self._token())
        self.assertEqual(claims["sub"], "1234567890")
        self.assertEqual(claims["email"], "student@gmail.com")

    def test_rejections(self):
        bad_tokens = [
            self._token(key=self.other_key),                       # forged signature
            self._token(aud="someone-elses-app"),                  # wrong audience
            self._token(iss="https://evil.example.com"),           # wrong issuer
            self._token(exp=int(time.time()) - 3600),              # expired
            self._token(email_verified=False),                     # unverified email
            jwt.encode({"sub": "x", "aud": self.CLIENT_ID}, "secret", algorithm="HS256"),  # alg confusion
            "not-a-jwt",
        ]
        for token in bad_tokens:
            with self.assertRaises(GoogleTokenError):
                self._verify(token)

    def test_requires_configuration(self):
        with self.assertRaises(GoogleTokenError):
            verify_google_id_token(self._token(), [], key_resolver=lambda _t: self.key.public_key())


class RazorpayTests(unittest.TestCase):
    def test_payment_signature(self):
        client = RazorpayClient("rzp_test_key", "secret123")
        signature = hmac.new(b"secret123", b"order_ABC123|pay_XYZ789", hashlib.sha256).hexdigest()
        self.assertTrue(client.verify_payment_signature("order_ABC123", "pay_XYZ789", signature))
        self.assertTrue(client.verify_payment_signature("order_ABC123", "pay_XYZ789", signature.upper()))
        self.assertFalse(client.verify_payment_signature("order_ABC123", "pay_OTHER1", signature))
        self.assertFalse(client.verify_payment_signature("order_ABC123", "pay_XYZ789", "0" * 64))
        self.assertFalse(RazorpayClient("k", "").verify_payment_signature("order_ABC123", "pay_XYZ789", signature))

    def test_webhook_signature(self):
        body = json.dumps({"event": "order.paid"}).encode()
        client = RazorpayClient("k", "s", webhook_secret="hook-secret")
        good = hmac.new(b"hook-secret", body, hashlib.sha256).hexdigest()
        self.assertTrue(client.verify_webhook_signature(body, good))
        self.assertFalse(client.verify_webhook_signature(body + b" ", good))
        self.assertFalse(RazorpayClient("k", "s").verify_webhook_signature(body, good))  # no secret set

    def test_create_order(self):
        session = FakeSession(FakeResponse(200, {"id": "order_TEST123", "amount": 49900, "currency": "INR"}))
        client = RazorpayClient("rzp_test_key", "secret", session=session)
        order = client.create_order(49900, "INR", "rcpt_1", {"purpose": "course", "user_id": 7})
        self.assertEqual(order["id"], "order_TEST123")
        url, kwargs = session.calls[0]
        self.assertEqual(url, "https://api.razorpay.com/v1/orders")
        self.assertEqual(kwargs["auth"], ("rzp_test_key", "secret"))
        self.assertEqual(kwargs["json"]["amount"], 49900)
        self.assertEqual(kwargs["json"]["notes"]["user_id"], "7")

    def test_create_order_errors(self):
        for response in (
            FakeResponse(401, {"error": {"description": "Authentication failed"}}),
            FakeResponse(200, {"id": "order_X", "amount": 100}),  # amount mismatch
            FakeResponse(500, None),
        ):
            client = RazorpayClient("k", "s", session=FakeSession(response))
            with self.assertRaises(RazorpayError):
                client.create_order(49900, "INR", "rcpt", {})


class SmsProviderTests(unittest.TestCase):
    def test_msg91(self):
        session = FakeSession(FakeResponse(200, {"type": "success"}))
        send_msg91(session, "auth", "tmpl", "+919876543210", "123456")
        url, kwargs = session.calls[0]
        self.assertIn("control.msg91.com/api/v5/otp", url)
        self.assertEqual(kwargs["params"], {"template_id": "tmpl", "mobile": "919876543210", "otp": "123456"})
        self.assertEqual(kwargs["headers"]["authkey"], "auth")
        with self.assertRaises(SmsError):
            send_msg91(FakeSession(FakeResponse(200, {"type": "error", "message": "bad"})), "a", "t", "+91", "1")
        with self.assertRaises(SmsError):
            send_msg91(session, "", "", "+919876543210", "123456")

    def test_fast2sms(self):
        session = FakeSession(FakeResponse(200, {"return": True}))
        send_fast2sms(session, "key", "+919876543210", "654321")
        self.assertEqual(session.calls[0][1]["json"], {"route": "otp", "variables_values": "654321", "numbers": "9876543210"})
        with self.assertRaises(SmsError):
            send_fast2sms(FakeSession(FakeResponse(200, {"return": False})), "key", "+919876543210", "1")

    def test_twilio(self):
        session = FakeSession(FakeResponse(201, {}))
        send_twilio(session, "AC1", "tok", "+15550001111", "+919876543210", "hi")
        self.assertEqual(session.calls[0][1]["data"]["From"], "+15550001111")
        send_twilio(session, "AC1", "tok", "MG123", "+919876543210", "hi")
        self.assertEqual(session.calls[1][1]["data"]["MessagingServiceSid"], "MG123")
        with self.assertRaises(SmsError):
            send_twilio(FakeSession(FakeResponse(400, {"message": "bad"})), "AC1", "tok", "+1", "+91", "hi")


if __name__ == "__main__":
    unittest.main()


class DatabaseUrlTests(unittest.TestCase):
    def test_postgres_address(self):
        config = database_from_url(
            "postgres://app_user:p%40ss%3Aword@dpg-abc.singapore-postgres.render.com/learn_db?sslmode=require"
        )
        self.assertEqual(config["ENGINE"], "django.db.backends.postgresql")
        self.assertEqual(config["NAME"], "learn_db")
        self.assertEqual(config["USER"], "app_user")
        self.assertEqual(config["PASSWORD"], "p@ss:word")
        self.assertEqual(config["HOST"], "dpg-abc.singapore-postgres.render.com")
        self.assertEqual(config["PORT"], "5432")
        self.assertEqual(config["OPTIONS"], {"sslmode": "require"})

    def test_internal_address_and_mysql(self):
        config = database_from_url("postgresql://u:pw@dpg-abc-a:6543/db")
        self.assertEqual((config["HOST"], config["PORT"], config["NAME"]), ("dpg-abc-a", "6543", "db"))
        self.assertNotIn("OPTIONS", config)
        mysql = database_from_url("mysql://u:pw@db.example.com/shop")
        self.assertEqual(mysql["ENGINE"], "django.db.backends.mysql")
        self.assertEqual(mysql["PORT"], "3306")
        self.assertEqual(mysql["OPTIONS"]["charset"], "utf8mb4")

    def test_rejects_unusable_addresses(self):
        for url in ("sqlite:///db.sqlite3", "postgres://u:pw@host/", "postgres://u:pw@host:notaport/db",
                    "postgres:///db"):
            with self.assertRaises(ValueError, msg=url):
                database_from_url(url)
