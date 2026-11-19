import hashlib
import hmac
import json
from unittest.mock import patch

from django.test import override_settings

from courses.models import Enrollment
from payments.models import Payment

from .helpers import ApiTestCase


@override_settings(APP_ENV="local", PAYMENTS_MODE="mock")
class MockPaymentTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.course = self.make_course("Python for Beginners", price="499", lessons=2)
        self.user = self.make_user()
        self.login_as(self.user)

    def test_purchase_flow(self):
        response = self.client.post("/api/payments/course-order", {"course_id": self.course.pk, "amount": 1}, format="json")
        self.assertEqual(response.status_code, 201, response.content)
        checkout = self.data(response)
        self.assertEqual(checkout["mode"], "mock")
        self.assertEqual(checkout["amount"], 49900)  # price comes from the server, not the request
        response = self.client.post("/api/payments/mock-complete", {"order_id": checkout["order_id"]}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(self.data(response)["status"], "paid")
        self.assertTrue(Enrollment.objects.filter(user=self.user, course=self.course, source="purchase").exists())
        # Completing again changes nothing.
        self.client.post("/api/payments/mock-complete", {"order_id": checkout["order_id"]}, format="json")
        self.assertEqual(Enrollment.objects.filter(user=self.user, course=self.course).count(), 1)
        self.assertEqual(len(self.data(self.client.get("/api/me/payments"))), 1)
        # Already owned: no second order.
        response = self.client.post("/api/payments/course-order", {"course_id": self.course.pk}, format="json")
        self.assertEqual(response.status_code, 409)

    def test_other_user_cannot_complete_my_order(self):
        checkout = self.data(self.client.post("/api/payments/course-order", {"course_id": self.course.pk}, format="json"))
        self.login_as(self.make_user(email="other@example.com"))
        response = self.client.post("/api/payments/mock-complete", {"order_id": checkout["order_id"]}, format="json")
        self.assertEqual(response.status_code, 404)

    def test_free_and_empty_courses_cannot_be_bought(self):
        free = self.make_course("Free One", price="0")
        empty = self.make_course("Coming Soon", price="299", lessons=0)
        self.assertEqual(self.client.post("/api/payments/course-order", {"course_id": free.pk}, format="json").status_code, 409)
        self.assertEqual(self.client.post("/api/payments/course-order", {"course_id": empty.pk}, format="json").status_code, 409)

    @override_settings(APP_ENV="production")
    def test_mock_mode_is_impossible_in_production(self):
        # No Razorpay keys configured → real mode refuses instead of simulating.
        response = self.client.post("/api/payments/course-order", {"course_id": self.course.pk}, format="json")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(self.client.post("/api/payments/mock-complete", {"order_id": "order_mock_" + "a" * 20}, format="json").status_code, 404)


@override_settings(
    APP_ENV="production",
    PAYMENTS_MODE="razorpay",
    RAZORPAY_KEY_ID="rzp_test_abc",
    RAZORPAY_KEY_SECRET="topsecret",
    RAZORPAY_WEBHOOK_SECRET="hooksecret",
)
class RazorpayPaymentTests(ApiTestCase):
    ORDER = {"id": "order_TEST12345", "amount": 49900, "currency": "INR"}

    def setUp(self):
        super().setUp()
        self.course = self.make_course("Python for Beginners", price="499", lessons=2)
        self.user = self.make_user()
        self.login_as(self.user)
        with patch("payments.razorpay.RazorpayClient.create_order", return_value=self.ORDER):
            response = self.client.post("/api/payments/course-order", {"course_id": self.course.pk}, format="json")
        self.assertEqual(response.status_code, 201, response.content)
        self.checkout = self.data(response)

    @staticmethod
    def sign(order_id, payment_id, secret="topsecret"):
        return hmac.new(secret.encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256).hexdigest()

    def verify(self, payment_id="pay_TEST999", signature=None):
        return self.client.post("/api/payments/verify", {
            "order_id": "order_TEST12345",
            "payment_id": payment_id,
            "signature": signature or self.sign("order_TEST12345", payment_id),
        }, format="json")

    def test_checkout_payload(self):
        self.assertEqual(self.checkout["key_id"], "rzp_test_abc")
        self.assertEqual(self.checkout["order_id"], "order_TEST12345")
        self.assertNotIn("topsecret", json.dumps(self.checkout))  # the secret never leaves the server

    def test_forged_signature_is_rejected(self):
        response = self.verify(signature=self.sign("order_TEST12345", "pay_TEST999", secret="guess"))
        self.assertEqual(response.status_code, 400)
        self.assertEqual(self.error(response)["code"], "invalid_signature")
        self.assertFalse(Enrollment.objects.filter(user=self.user).exists())

    def test_valid_signature_enrolls_once(self):
        self.assertEqual(self.data(self.verify())["status"], "paid")
        self.assertEqual(self.data(self.verify())["status"], "paid")
        self.assertEqual(Enrollment.objects.filter(user=self.user, course=self.course).count(), 1)
        self.assertEqual(Payment.objects.get().provider_payment_id, "pay_TEST999")

    def test_other_user_cannot_verify_my_order(self):
        self.login_as(self.make_user(email="other@example.com"))
        self.assertEqual(self.verify().status_code, 404)

    def webhook(self, payload, secret="hooksecret"):
        body = json.dumps(payload).encode()
        signature = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        return self.client.generic("POST", "/api/payments/webhook", body, content_type="application/json",
                                   HTTP_X_RAZORPAY_SIGNATURE=signature)

    def test_webhook(self):
        event = {"event": "payment.captured", "payload": {"payment": {"entity": {
            "id": "pay_HOOK1", "order_id": "order_TEST12345", "amount": 49900}}}}
        self.assertEqual(self.webhook(event, secret="wrong").status_code, 400)
        self.assertFalse(Enrollment.objects.exists())
        wrong_amount = json.loads(json.dumps(event))
        wrong_amount["payload"]["payment"]["entity"]["amount"] = 100
        self.assertEqual(self.webhook(wrong_amount).status_code, 200)
        self.assertFalse(Enrollment.objects.exists())
        self.assertEqual(self.webhook(event).status_code, 200)
        self.assertTrue(Enrollment.objects.filter(user=self.user, course=self.course).exists())
        self.assertEqual(Payment.objects.get().status, "paid")
