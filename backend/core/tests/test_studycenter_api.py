from datetime import time, timedelta
from decimal import Decimal

from django.test import override_settings
from django.utils import timezone

from core.models import SiteSettings
from core.utils import add_months
from payments.models import Payment
from studycenter.models import Batch, Booking, Shift

from .helpers import ApiTestCase


@override_settings(APP_ENV="local", PAYMENTS_MODE="mock", BOOKING_HOLD_MINUTES=10)
class BatchBookingTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.batch = Batch.objects.create(
            title="Python for Beginners", start_time=time(16), end_time=time(18),
            start_date=timezone.localdate() + timedelta(days=10), total_seats=10, seats_per_row=5,
            fee=Decimal("3000"), booking_amount=Decimal("3000"),
        )
        self.asha = self.make_user()
        self.ravi = self.make_user(email="ravi@example.com", name="Ravi")

    def book(self, seat_no, batch=None):
        batch = batch or self.batch
        return self.client.post(f"/api/study-center/batches/{batch.pk}/book", {"seat_no": seat_no}, format="json")

    def seat_status(self, seat_no):
        seats = self.data(self.client.get(f"/api/study-center/batches/{self.batch.pk}"))["seats"]
        return next(s["status"] for s in seats if s["no"] == seat_no)

    def test_listing_and_seat_map(self):
        batches = self.data(self.client.get("/api/study-center/batches"))
        self.assertEqual(batches[0]["seats_left"], 10)
        self.assertEqual(batches[0]["fee_paise"], 300000)
        detail = self.data(self.client.get(f"/api/study-center/batches/{self.batch.pk}"))
        self.assertEqual([s["label"] for s in detail["seats"][:6]], ["A1", "A2", "A3", "A4", "A5", "B1"])

    def test_hold_then_pay(self):
        self.login_as(self.asha)
        response = self.book(3)
        self.assertEqual(response.status_code, 201, response.content)
        body = self.data(response)
        self.assertEqual(body["booking"]["status"], "held")
        self.assertEqual(body["booking"]["seat_label"], "A3")
        self.assertEqual(body["checkout"]["amount"], 300000)
        self.assertEqual(self.seat_status(3), "mine")

        self.login_as(self.ravi)
        self.assertEqual(self.seat_status(3), "held")
        response = self.book(3)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.error(response)["code"], "seat_taken")

        self.login_as(self.asha)
        self.assertEqual(self.error(self.book(4))["code"], "already_booked")  # one seat per student per batch
        response = self.client.post("/api/payments/mock-complete", {"order_id": body["checkout"]["order_id"]}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.data(response)["booking"]["status"], "confirmed")
        self.login_as(self.ravi)
        self.assertEqual(self.seat_status(3), "booked")
        self.assertEqual(self.data(self.client.get("/api/study-center/batches"))[0]["seats_left"], 9)

    def test_expired_hold_frees_the_seat(self):
        self.login_as(self.asha)
        checkout = self.data(self.book(3))["checkout"]
        Booking.objects.update(hold_expires_at=timezone.now() - timedelta(minutes=1))
        self.login_as(self.ravi)
        self.assertEqual(self.book(3).status_code, 201)
        # Asha pays too late: the seat is gone, so the payment is flagged for refund.
        self.login_as(self.asha)
        response = self.client.post("/api/payments/mock-complete", {"order_id": checkout["order_id"]}, format="json")
        self.assertEqual(self.data(response)["status"], "refund_due")
        self.assertEqual(Payment.objects.get(provider_order_id=checkout["order_id"]).status, "refund_due")
        self.assertEqual(Booking.objects.get(user=self.asha).status, "expired")

    def test_late_payment_still_confirms_if_seat_is_free(self):
        self.login_as(self.asha)
        checkout = self.data(self.book(3))["checkout"]
        Booking.objects.update(hold_expires_at=timezone.now() - timedelta(minutes=1))
        response = self.client.post("/api/payments/mock-complete", {"order_id": checkout["order_id"]}, format="json")
        self.assertEqual(self.data(response)["status"], "paid")
        self.assertEqual(Booking.objects.get(user=self.asha).status, "confirmed")

    def test_pay_at_center_batches_confirm_immediately(self):
        self.batch.booking_amount = Decimal("0")
        self.batch.save()
        self.login_as(self.asha)
        body = self.data(self.book(1))
        self.assertEqual(body["booking"]["status"], "confirmed")
        self.assertIsNone(body["checkout"])

    def test_validation_and_closed_batches(self):
        self.login_as(self.asha)
        response = self.book(11)
        self.assertEqual(response.status_code, 422)
        self.assertIn("seat_no", self.error(response)["fields"])
        self.batch.is_active = False
        self.batch.save()
        self.assertEqual(self.book(1).status_code, 409)
        self.logout_client()
        self.assertEqual(self.book(1).status_code, 401)

    def test_cancel_and_privacy(self):
        self.login_as(self.asha)
        booking = self.data(self.book(2))["booking"]
        self.login_as(self.ravi)
        self.assertEqual(self.client.get(f"/api/me/bookings/{booking['id']}").status_code, 404)
        self.assertEqual(self.client.post(f"/api/me/bookings/{booking['id']}/cancel").status_code, 404)
        self.login_as(self.asha)
        response = self.client.post(f"/api/me/bookings/{booking['id']}/cancel")
        self.assertEqual(self.data(response)["status"], "cancelled")
        self.assertEqual(self.seat_status(2), "available")
        self.assertEqual(len(self.data(self.client.get("/api/me/bookings"))), 1)


@override_settings(APP_ENV="local", PAYMENTS_MODE="mock")
class LibraryBookingTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        site = SiteSettings.load()
        site.library_total_desks = 12
        site.library_desks_per_row = 6
        site.library_max_months = 6
        site.library_advance_days = 60
        site.save()
        self.morning = Shift.objects.create(name="Morning", start_time=time(10), end_time=time(14), monthly_fee=Decimal("400"))
        self.evening = Shift.objects.create(name="Evening", start_time=time(14), end_time=time(18), monthly_fee=Decimal("400"))
        self.full = Shift.objects.create(name="Full day", start_time=time(10), end_time=time(18), monthly_fee=Decimal("700"))
        self.today = timezone.localdate()
        self.asha = self.make_user()
        self.ravi = self.make_user(email="ravi@example.com", name="Ravi")

    def book(self, shift, seat_no, start=None, months=1):
        return self.client.post("/api/study-center/library/book", {
            "shift_id": shift.pk, "seat_no": seat_no, "start_date": (start or self.today).isoformat(), "months": months,
        }, format="json")

    def test_availability_and_price(self):
        response = self.client.get(
            f"/api/study-center/library/availability?shift_id={self.morning.pk}&start_date={self.today.isoformat()}&months=2"
        )
        self.assertEqual(response.status_code, 200, response.content)
        body = self.data(response)
        self.assertEqual(body["amount_paise"], 80000)
        self.assertEqual(len(body["seats"]), 12)
        self.assertEqual(body["end_date"], add_months(self.today, 2).isoformat())
        info = self.data(self.client.get("/api/study-center"))
        self.assertEqual(len(info["shifts"]), 3)

    def test_overlapping_shifts_and_dates(self):
        self.login_as(self.asha)
        self.assertEqual(self.book(self.morning, 1).status_code, 201)
        self.login_as(self.ravi)
        self.assertEqual(self.error(self.book(self.full, 1))["code"], "seat_taken")   # full day overlaps morning
        self.assertEqual(self.book(self.evening, 1).status_code, 201)                    # evening does not
        after = add_months(self.today, 1)                                                 # Asha's booking ends here
        self.login_as(self.make_user(email="third@example.com"))
        self.assertEqual(self.book(self.morning, 1, start=after).status_code, 201)

    def test_one_desk_per_student_per_time(self):
        self.login_as(self.asha)
        self.assertEqual(self.book(self.morning, 1).status_code, 201)
        self.assertEqual(self.error(self.book(self.morning, 2))["code"], "already_booked")

    def test_validation(self):
        self.login_as(self.asha)
        self.assertEqual(self.book(self.morning, 1, start=self.today - timedelta(days=1)).status_code, 422)
        self.assertEqual(self.book(self.morning, 1, start=self.today + timedelta(days=90)).status_code, 422)
        self.assertEqual(self.book(self.morning, 1, months=7).status_code, 422)
        self.assertEqual(self.book(self.morning, 13).status_code, 422)
        site = SiteSettings.load()
        site.library_enabled = False
        site.save()
        self.assertEqual(self.book(self.morning, 1).status_code, 409)

    def test_pay_and_confirm(self):
        self.login_as(self.asha)
        body = self.data(self.book(self.full, 5, months=3))
        self.assertEqual(body["checkout"]["amount"], 210000)
        response = self.client.post("/api/payments/mock-complete", {"order_id": body["checkout"]["order_id"]}, format="json")
        booking = self.data(response)["booking"]
        self.assertEqual(booking["status"], "confirmed")
        self.assertEqual(booking["seat_label"], "A5")
        self.assertEqual(booking["months"], 3)
