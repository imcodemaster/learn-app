import re
from datetime import timedelta
from unittest.mock import patch

from django.test import override_settings
from django.utils import timezone

from accounts.google import GoogleTokenError
from accounts.models import AuthToken, OtpCode, User
from core.utils import hash_token

from .helpers import STRONG_PASSWORD, ApiTestCase


@override_settings(APP_ENV="local", SMS_BACKEND="console")
class EmailAuthTests(ApiTestCase):
    def test_register_login_me_logout(self):
        response = self.client.post(
            "/api/auth/register",
            {"name": "Asha", "email": "Asha@Example.com", "password": STRONG_PASSWORD},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        body = self.data(response)
        token = body["token"]
        self.assertTrue(token.startswith("li_"))
        self.assertEqual(body["user"]["email"], "asha@example.com")
        self.assertTrue(body["is_new"])
        # Only a hash of the token is stored.
        self.assertFalse(AuthToken.objects.filter(token_hash=token).exists())
        self.assertTrue(AuthToken.objects.filter(token_hash=hash_token(token)).exists())

        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        self.assertEqual(self.data(self.client.get("/api/me"))["name"], "Asha")
        self.assertEqual(self.client.post("/api/auth/logout").status_code, 200)
        response = self.client.get("/api/me")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(self.error(response)["code"], "session_expired")

        self.logout_client()
        response = self.client.post("/api/auth/login", {"email": "ASHA@example.com", "password": STRONG_PASSWORD}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertFalse(self.data(response)["is_new"])

    def test_register_validation(self):
        self.make_user(email="taken@example.com")
        response = self.client.post("/api/auth/register",
                                    {"name": "X", "email": "taken@example.com", "password": STRONG_PASSWORD}, format="json")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.error(response)["code"], "email_taken")

        response = self.client.post("/api/auth/register",
                                    {"name": "X", "email": "new@example.com", "password": "password"}, format="json")
        self.assertEqual(response.status_code, 422)
        self.assertIn("password", self.error(response)["fields"])

        response = self.client.post("/api/auth/register",
                                    {"name": "X", "email": "not-an-email", "password": STRONG_PASSWORD}, format="json")
        self.assertEqual(response.status_code, 422)
        self.assertIn("email", self.error(response)["fields"])

    def test_wrong_password_and_unknown_email_look_the_same(self):
        self.make_user()
        wrong = self.client.post("/api/auth/login", {"email": "asha@example.com", "password": "Wrong12345"}, format="json")
        unknown = self.client.post("/api/auth/login", {"email": "nobody@example.com", "password": "Wrong12345"}, format="json")
        self.assertEqual(wrong.status_code, 401)
        self.assertEqual(unknown.status_code, 401)
        self.assertEqual(self.error(wrong), self.error(unknown))

    def test_login_is_rate_limited(self):
        self.make_user()
        for _ in range(10):
            self.client.post("/api/auth/login", {"email": "asha@example.com", "password": "Wrong12345"}, format="json")
        response = self.client.post("/api/auth/login", {"email": "asha@example.com", "password": STRONG_PASSWORD}, format="json")
        self.assertEqual(response.status_code, 429)
        self.assertIn("Retry-After", response.headers)

    def test_disabled_user_is_signed_out(self):
        user = self.make_user()
        self.login_as(user)
        user.is_active = False
        user.save()
        self.assertEqual(self.client.get("/api/me").status_code, 401)

    def test_profile_and_password_change(self):
        user = self.make_user()
        other_device = self.token_for(user)
        self.login_as(user)
        response = self.client.patch("/api/me", {"name": "Asha Rawat", "is_staff": True, "email": "x@y.com"}, format="json")
        self.assertEqual(response.status_code, 200)
        user.refresh_from_db()
        self.assertEqual(user.name, "Asha Rawat")
        self.assertFalse(user.is_staff)          # mass assignment ignored
        self.assertEqual(user.email, "asha@example.com")

        response = self.client.post("/api/me/password", {"current_password": "Wrong12345", "new_password": "Newpass2026x"}, format="json")
        self.assertEqual(response.status_code, 422)
        response = self.client.post("/api/me/password", {"current_password": STRONG_PASSWORD, "new_password": "Newpass2026x"}, format="json")
        self.assertEqual(response.status_code, 200)
        user.refresh_from_db()
        self.assertTrue(user.check_password("Newpass2026x"))
        self.assertFalse(AuthToken.objects.filter(token_hash=hash_token(other_device)).exists())  # other devices signed out
        self.assertEqual(self.client.get("/api/me").status_code, 200)  # this device stays signed in

    def test_forgot_and_reset_password(self):
        user = self.make_user()
        with patch("accounts.views.send_mail") as send_mail:
            response = self.client.post("/api/auth/password/forgot", {"email": "asha@example.com"}, format="json")
            self.assertEqual(response.status_code, 200)
            self.assertTrue(send_mail.called)
            code = re.search(r"\b(\d{6})\b", send_mail.call_args[0][1]).group(1)

        with patch("accounts.views.send_mail") as send_mail:
            response = self.client.post("/api/auth/password/forgot", {"email": "nobody@example.com"}, format="json")
            self.assertEqual(response.status_code, 200)  # same answer for unknown emails
            self.assertFalse(send_mail.called)

        response = self.client.post("/api/auth/password/reset",
                                    {"email": "asha@example.com", "code": "000000" if code != "000000" else "111111",
                                     "password": "Brandnew2026"}, format="json")
        self.assertEqual(response.status_code, 422)
        response = self.client.post("/api/auth/password/reset",
                                    {"email": "asha@example.com", "code": code, "password": "Brandnew2026"}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        user.refresh_from_db()
        self.assertTrue(user.check_password("Brandnew2026"))
        self.assertTrue(user.email_verified)

    def test_delete_account(self):
        user = self.make_user()
        self.login_as(user)
        self.assertEqual(self.client.post("/api/me/delete", {"confirm": "yes"}, format="json").status_code, 422)
        self.assertEqual(self.client.post("/api/me/delete", {"confirm": "DELETE"}, format="json").status_code, 200)
        user.refresh_from_db()
        self.assertIsNone(user.email)
        self.assertFalse(user.is_active)
        self.assertEqual(user.name, "Deleted user")
        self.assertEqual(self.client.get("/api/me").status_code, 401)
        self.logout_client()
        # The email address can be used again.
        response = self.client.post("/api/auth/register",
                                    {"name": "Asha", "email": "asha@example.com", "password": STRONG_PASSWORD}, format="json")
        self.assertEqual(response.status_code, 201)


@override_settings(APP_ENV="local", SMS_BACKEND="console", OTP_RESEND_SECONDS=60, OTP_MAX_ATTEMPTS=5)
class PhoneOtpTests(ApiTestCase):
    def send(self, phone="98765 43210"):
        return self.client.post("/api/auth/otp/send", {"phone": phone}, format="json")

    def test_otp_login_creates_account(self):
        response = self.send()
        self.assertEqual(response.status_code, 200, response.content)
        body = self.data(response)
        self.assertEqual(body["phone"], "+919876543210")
        code = body["debug_code"]
        stored = OtpCode.objects.get(destination="+919876543210")
        self.assertNotEqual(stored.code_hash, code)  # stored hashed

        wrong = "000000" if code != "000000" else "111111"
        response = self.client.post("/api/auth/otp/verify", {"phone": "9876543210", "code": wrong}, format="json")
        self.assertEqual(response.status_code, 422)

        response = self.client.post("/api/auth/otp/verify", {"phone": "9876543210", "code": code, "name": "Ravi"}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        body = self.data(response)
        self.assertTrue(body["is_new"])
        self.assertEqual(body["user"]["phone"], "+919876543210")
        self.assertEqual(body["user"]["name"], "Ravi")

        # A code works only once.
        response = self.client.post("/api/auth/otp/verify", {"phone": "9876543210", "code": code}, format="json")
        self.assertEqual(response.status_code, 422)

    def test_invalid_phone(self):
        response = self.send("12345")
        self.assertEqual(response.status_code, 422)
        self.assertIn("phone", self.error(response)["fields"])

    def test_resend_cooldown(self):
        self.assertEqual(self.send().status_code, 200)
        response = self.send()
        self.assertEqual(response.status_code, 429)

    def test_attempt_limit(self):
        code = self.data(self.send())["debug_code"]
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(5):
            self.client.post("/api/auth/otp/verify", {"phone": "9876543210", "code": wrong}, format="json")
        response = self.client.post("/api/auth/otp/verify", {"phone": "9876543210", "code": code}, format="json")
        self.assertEqual(response.status_code, 429)
        self.assertEqual(self.error(response)["code"], "too_many_attempts")

    def test_expired_code(self):
        code = self.data(self.send())["debug_code"]
        OtpCode.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        response = self.client.post("/api/auth/otp/verify", {"phone": "9876543210", "code": code}, format="json")
        self.assertEqual(response.status_code, 422)

    @override_settings(APP_ENV="production")
    def test_console_sms_refused_in_production(self):
        response = self.send()
        self.assertEqual(response.status_code, 502)
        self.assertFalse(OtpCode.objects.exists())  # the unsent code was discarded


@override_settings(GOOGLE_CLIENT_IDS=["web-client.apps.googleusercontent.com"])
class GoogleLoginTests(ApiTestCase):
    CLAIMS = {"sub": "google-123", "email": "asha@gmail.com", "email_verified": True, "name": "Asha G",
              "picture": "https://lh3.googleusercontent.com/a/photo"}

    def post(self):
        return self.client.post("/api/auth/google", {"id_token": "x" * 60}, format="json")

    def test_new_user(self):
        with patch("accounts.views.verify_google_id_token", return_value=self.CLAIMS):
            response = self.post()
        self.assertEqual(response.status_code, 200, response.content)
        body = self.data(response)
        self.assertTrue(body["is_new"])
        self.assertTrue(body["user"]["google_linked"])
        self.assertEqual(body["user"]["email"], "asha@gmail.com")

    def test_links_existing_unverified_account_safely(self):
        user = self.make_user(email="asha@gmail.com", email_verified=False)
        old_token = self.token_for(user)
        with patch("accounts.views.verify_google_id_token", return_value=self.CLAIMS):
            response = self.post()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.data(response)["user"]["id"], user.pk)
        user.refresh_from_db()
        self.assertEqual(user.google_sub, "google-123")
        self.assertTrue(user.email_verified)
        self.assertFalse(user.has_usable_password())  # unproven password removed
        self.assertFalse(AuthToken.objects.filter(token_hash=hash_token(old_token)).exists())

    def test_bad_token(self):
        with patch("accounts.views.verify_google_id_token", side_effect=GoogleTokenError("bad")):
            response = self.post()
        self.assertEqual(response.status_code, 401)
        self.assertEqual(self.error(response)["code"], "invalid_google_token")

    @override_settings(GOOGLE_CLIENT_IDS=[])
    def test_not_configured(self):
        self.assertEqual(self.post().status_code, 503)

    def test_blocked_user(self):
        User.objects.create_user(email="asha@gmail.com", google_sub="google-123", is_active=False)
        with patch("accounts.views.verify_google_id_token", return_value=self.CLAIMS):
            self.assertEqual(self.post().status_code, 403)
