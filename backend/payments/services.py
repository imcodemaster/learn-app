import logging
import secrets

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from core.api import ApiError, payments_mode
from core.models import SiteSettings
from core.utils import iso_utc
from courses.models import Enrollment

from .models import Payment
from .razorpay import RazorpayClient, RazorpayError

logger = logging.getLogger("learnincreation")


def razorpay_client() -> RazorpayClient:
    return RazorpayClient(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET, settings.RAZORPAY_WEBHOOK_SECRET)


def create_order(user, *, purpose: str, amount_paise: int, description: str, course=None, booking=None) -> Payment:
    """Creates a Razorpay order (or a simulated one in test mode) for an amount taken from our DB."""
    if amount_paise < 100:
        raise ApiError(422, "amount_too_small", "The minimum online payment is ₹1.")
    mode = payments_mode()
    receipt = "rcpt_" + secrets.token_hex(12)
    if mode == "mock":
        order_id = "order_mock_" + secrets.token_hex(10)
    else:
        client = razorpay_client()
        if not client.configured:
            raise ApiError(503, "payments_not_configured", "Online payments are not set up yet. Please contact us.")
        notes = {"purpose": purpose, "user_id": user.pk}
        if course is not None:
            notes["course_id"] = course.pk
        if booking is not None:
            notes["booking_code"] = booking.code
        try:
            order = client.create_order(amount_paise, "INR", receipt, notes)
        except RazorpayError as exc:
            logger.error("Razorpay order failed: %s", exc)
            raise ApiError(502, "payment_gateway_error", "Could not start the payment. Please try again.") from exc
        order_id = order["id"]
    return Payment.objects.create(
        user=user,
        purpose=purpose,
        course=course,
        booking=booking,
        description=description[:255],
        amount_paise=amount_paise,
        currency="INR",
        provider=mode,
        provider_order_id=order_id,
        receipt=receipt,
    )


def checkout_payload(payment: Payment, user, timeout_seconds: int | None = None) -> dict:
    site = SiteSettings.load()
    return {
        "payment_id": payment.pk,
        "mode": payment.provider,
        "key_id": settings.RAZORPAY_KEY_ID if payment.provider == "razorpay" else "",
        "order_id": payment.provider_order_id,
        "amount": payment.amount_paise,
        "currency": payment.currency,
        "name": site.org_name,
        "description": payment.description,
        "prefill": {"name": user.name or "", "email": user.email or "", "contact": user.phone or ""},
        "timeout_seconds": timeout_seconds,
    }


def fulfill(payment_id: int, provider_payment_id: str) -> Payment:
    """
    Marks a payment as paid and delivers what was bought. Safe to call more
    than once (from the app and from the webhook) — only the first call acts.
    """
    from studycenter.services import confirm_booking_after_payment

    with transaction.atomic():
        payment = Payment.objects.select_for_update().get(pk=payment_id)
        if payment.status in (Payment.Status.PAID, Payment.Status.REFUND_DUE, Payment.Status.REFUNDED):
            return payment
        payment.status = Payment.Status.PAID
        payment.provider_payment_id = provider_payment_id
        payment.paid_at = timezone.now()
        payment.failure_reason = ""
        if payment.purpose == Payment.Purpose.COURSE and payment.course_id:
            Enrollment.objects.get_or_create(
                user_id=payment.user_id,
                course_id=payment.course_id,
                defaults={"source": Enrollment.Source.PURCHASE, "payment": payment},
            )
        elif payment.purpose == Payment.Purpose.BOOKING and payment.booking_id:
            if not confirm_booking_after_payment(payment.booking_id):
                payment.status = Payment.Status.REFUND_DUE
                payment.admin_note = "Seat was no longer available when the payment arrived. Refund the student."
        payment.save()
    return payment


def payment_item(payment: Payment) -> dict:
    return {
        "id": payment.pk,
        "description": payment.description,
        "amount_paise": payment.amount_paise,
        "currency": payment.currency,
        "status": payment.status,
        "purpose": payment.purpose,
        "course_id": payment.course_id,
        "booking_id": payment.booking_id,
        "provider_payment_id": payment.provider_payment_id,
        "created_at": iso_utc(payment.created_at),
        "paid_at": iso_utc(payment.paid_at),
    }


def payment_result(request, payment: Payment) -> dict:
    from studycenter.presenters import booking_payload

    message = {
        Payment.Status.PAID: "Payment successful.",
        Payment.Status.REFUND_DUE: "We received your payment, but the seat was released before it arrived. "
                                   "We'll refund you — please contact us if you have questions.",
    }.get(payment.status, "Payment recorded.")
    booking = payment.booking if payment.booking_id else None
    return {
        "status": payment.status,
        "purpose": payment.purpose,
        "course_id": payment.course_id,
        "booking": booking_payload(booking) if booking is not None else None,
        "payment": payment_item(payment),
        "message": message,
    }
