"""Behaviour that matters on the live server (Render): sign-in options, first admin, sample data."""

import os
from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import override_settings

from accounts.models import User
from courses.models import Course

from .helpers import STRONG_PASSWORD, ApiTestCase


class AppInfoSignInOptionsTests(ApiTestCase):
    def auth(self):
        response = self.client.get("/api/app/info")
        self.assertEqual(response.status_code, 200, response.content)
        return self.data(response)["auth"]

    @override_settings(APP_ENV="local", SMS_BACKEND="console")
    def test_phone_sign_in_available_for_local_testing(self):
        self.assertTrue(self.auth()["phone_enabled"])

    @override_settings(APP_ENV="production", SMS_BACKEND="console")
    def test_phone_sign_in_hidden_without_sms_provider(self):
        self.assertFalse(self.auth()["phone_enabled"])

    @override_settings(APP_ENV="production", SMS_BACKEND="msg91")
    def test_phone_sign_in_shown_with_sms_provider(self):
        self.assertTrue(self.auth()["phone_enabled"])


class EnsureAdminTests(ApiTestCase):
    def run_command(self, **env):
        out = StringIO()
        with mock.patch.dict(os.environ):
            for key in ("ADMIN_EMAIL", "ADMIN_PASSWORD", "ADMIN_NAME"):
                os.environ.pop(key, None)
            os.environ.update(env)
            call_command("ensure_admin", stdout=out)
        return out.getvalue()

    def test_creates_the_admin_once(self):
        output = self.run_command(ADMIN_EMAIL="Owner@LearnInCreation.com", ADMIN_PASSWORD=STRONG_PASSWORD,
                                  ADMIN_NAME="Vinay")
        self.assertIn("Created admin user owner@learnincreation.com", output)
        admin = User.objects.get(email="owner@learnincreation.com")
        self.assertTrue(admin.is_staff)
        self.assertTrue(admin.is_superuser)
        self.assertEqual(admin.name, "Vinay")
        self.assertTrue(admin.check_password(STRONG_PASSWORD))

        # Every deploy runs the command again: the account and its password stay as they are.
        output = self.run_command(ADMIN_EMAIL="owner@learnincreation.com", ADMIN_PASSWORD="Another2026pass")
        self.assertIn("already exists", output)
        admin.refresh_from_db()
        self.assertTrue(admin.check_password(STRONG_PASSWORD))
        self.assertEqual(User.objects.count(), 1)

    def test_does_nothing_when_not_configured(self):
        self.assertIn("not set", self.run_command())
        self.assertFalse(User.objects.exists())

    def test_refuses_a_weak_password(self):
        with self.assertRaises(CommandError):
            self.run_command(ADMIN_EMAIL="owner@learnincreation.com", ADMIN_PASSWORD="12345678")
        self.assertFalse(User.objects.exists())


class SampleDataIfEmptyTests(ApiTestCase):
    def test_samples_fill_only_an_empty_catalog(self):
        call_command("seed_demo", "--if-empty", stdout=StringIO())
        count = Course.objects.count()
        self.assertGreater(count, 0)

        Course.objects.order_by("id").first().delete()
        call_command("seed_demo", "--if-empty", stdout=StringIO())
        self.assertEqual(Course.objects.count(), count - 1)  # a sample course you deleted stays deleted


class ClientIpTests(ApiTestCase):
    """Rate limits must count each visitor separately behind Render's proxies."""

    def request(self, **meta):
        from django.test import RequestFactory

        return RequestFactory().get("/api/health", REMOTE_ADDR="10.1.2.3",
                                    HTTP_X_FORWARDED_FOR="6.6.6.6, 198.51.100.4, 10.9.9.9", **meta)

    @override_settings(CLIENT_IP_HEADER="HTTP_TRUE_CLIENT_IP", NUM_PROXIES=0)
    def test_trusted_header_gives_the_visitor_ip(self):
        from core.ratelimit import client_ip
        from core.throttling import AnonThrottle

        request = self.request(HTTP_TRUE_CLIENT_IP="203.0.113.7")
        self.assertEqual(client_ip(request), "203.0.113.7")
        self.assertEqual(AnonThrottle().get_ident(request), "203.0.113.7")

    @override_settings(CLIENT_IP_HEADER="HTTP_TRUE_CLIENT_IP", NUM_PROXIES=0)
    def test_missing_or_bad_header_falls_back_to_the_connection(self):
        from core.ratelimit import client_ip

        self.assertEqual(client_ip(self.request()), "10.1.2.3")
        self.assertEqual(client_ip(self.request(HTTP_TRUE_CLIENT_IP="not-an-ip")), "10.1.2.3")

    @override_settings(CLIENT_IP_HEADER="", NUM_PROXIES=0)
    def test_header_ignored_unless_configured(self):
        from core.ratelimit import client_ip

        self.assertEqual(client_ip(self.request(HTTP_TRUE_CLIENT_IP="203.0.113.7")), "10.1.2.3")
