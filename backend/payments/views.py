import json
import logging
import secrets

from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST
from rest_framework import serializers
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated

from core import ratelimit
from core.api import ApiError, not_found, ok, payments_mode
from courses.models import Course, Enrollment

from .models import Payment
from .services import checkout_payload, create_order, fulfill, payment_item, payment_result, razorpay_client

logger = logging.getLogger("learnincreation")


class CourseOrderSerializer(serializers.Serializer):
    course_id = serializers.IntegerField(min_value=1)


class BookingOrderSerializer(serializers.Serializer):
    booking_id = serializers.IntegerField(min_value=1)


class VerifySerializer(serializers.Serializer):
    order_id = serializers.RegexField(r"^order_[A-Za-z0-9]{6,40}$", max_length=60)
    payment_id = serializers.RegexField(r"^pay_[A-Za-z0-9]{6,40}$", max_length=60)
    signature = serializers.RegexField(r"^[A-Fa-f0-9]{64}$", max_length=64)


class MockCompleteSerializer(serializers.Serializer):
    order_id = serializers.RegexField(r"^order_mock_[a-f0-9]{20}$", max_length=40)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def course_order(request):
    serializer = CourseOrderSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    course = Course.objects.filter(pk=serializer.validated_data["course_id"], is_published=True).first()
    if course is None:
        raise not_found("Course not found.")
    if Enrollment.objects.filter(user=request.user, course=course).exists():
        raise ApiError(409, "already_enrolled", "You already have this course.")
    if course.is_free:
        raise ApiError(409, "course_is_free", "This course is free — just tap Enroll.")
    if not course.lessons.filter(is_published=True).exists():
        raise ApiError(409, "coming_soon", "Lessons for this course are coming soon.")
    ratelimit.hit(f"pay:user:{request.user.pk}", 30, 3600)
    payment = create_order(
        request.user,
        purpose=Payment.Purpose.COURSE,
        amount_paise=course.price_paise,
        description=f"Course: {course.title}",
        course=course,
    )
    return ok(checkout_payload(payment, request.user), 201)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def booking_order(request):
    from studycenter.models import Booking
    from studycenter.presenters import booking_description
    from studycenter.services import expire_stale_holds

    serializer = BookingOrderSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    expire_stale_holds()
    booking = (
        Booking.objects.select_related("batch", "shift")
        .filter(pk=serializer.validated_data["booking_id"], user=request.user)
        .first()
    )
    if booking is None:
        raise not_found("Booking not found.")
    if booking.status == Booking.Status.CONFIRMED:
        raise ApiError(409, "already_confirmed", "This booking is already confirmed.")
    if booking.status != Booking.Status.HELD or booking.hold_expires_at is None:
        raise ApiError(409, "hold_expired", "This seat hold has expired. Please book again.")
    remaining = int((booking.hold_expires_at - timezone.now()).total_seconds())
    if remaining < 30:
        raise ApiError(409, "hold_expired", "This seat hold has expired. Please book again.")
    ratelimit.hit(f"pay:user:{request.user.pk}", 30, 3600)
    payment = create_order(
        request.user,
        purpose=Payment.Purpose.BOOKING,
        amount_paise=booking.amount_paise,
        description=booking_description(booking),
        booking=booking,
    )
    return ok(checkout_payload(payment, request.user, timeout_seconds=max(60, remaining - 15)), 201)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def verify(request):
    serializer = VerifySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    payment = Payment.objects.filter(provider_order_id=data["order_id"], user=request.user).first()
    if payment is None:
        raise not_found("Payment not found.")
    if payment.provider != "razorpay":
        raise ApiError(400, "wrong_mode", "This payment was not made through Razorpay.")
    if not razorpay_client().verify_payment_signature(data["order_id"], data["payment_id"], data["signature"]):
        logger.warning("Invalid Razorpay signature for order %s (user %s)", data["order_id"], request.user.pk)
        raise ApiError(400, "invalid_signature",
                       "We couldn't verify this payment. If money was deducted, contact us with your payment ID.")
    payment = fulfill(payment.pk, data["payment_id"])
    return ok(payment_result(request, payment))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def mock_complete(request):
    """Test mode only: simulates a successful payment. Disabled in production."""
    if payments_mode() != "mock":
        raise not_found()
    serializer = MockCompleteSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    payment = Payment.objects.filter(
        provider_order_id=serializer.validated_data["order_id"], user=request.user, provider="mock"
    ).first()
    if payment is None:
        raise not_found("Payment not found.")
    payment = fulfill(payment.pk, "pay_mock_" + secrets.token_hex(8))
    return ok(payment_result(request, payment))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_payments(request):
    payments = Payment.objects.filter(
        user=request.user,
        status__in=[Payment.Status.PAID, Payment.Status.REFUND_DUE, Payment.Status.REFUNDED],
    ).order_by("-created_at")[:200]
    return ok([payment_item(p) for p in payments])


@csrf_exempt
@require_POST
def razorpay_webhook(request):
    """
    Razorpay → server notification. Makes sure a payment is recorded even if
    the app was closed right after paying. Configure in Razorpay Dashboard →
    Webhooks with events payment.captured, order.paid, payment.failed.
    """
    body = request.body
    if len(body) > 1_000_000:
        return JsonResponse({"error": {"code": "too_large", "message": "Payload too large."}}, status=413)
    if not razorpay_client().verify_webhook_signature(body, request.headers.get("X-Razorpay-Signature", "")):
        logger.warning("Rejected Razorpay webhook with a bad signature")
        return JsonResponse({"error": {"code": "invalid_signature", "message": "Invalid signature."}}, status=400)
    try:
        event = json.loads(body.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return JsonResponse({"error": {"code": "invalid_json", "message": "Invalid JSON."}}, status=400)

    name = event.get("event") if isinstance(event, dict) else None
    payload = event.get("payload") if isinstance(event, dict) else None
    entity = {}
    if isinstance(payload, dict) and isinstance(payload.get("payment"), dict):
        entity = payload["payment"].get("entity") or {}
    order_id = entity.get("order_id") if isinstance(entity, dict) else None
    payment_id = entity.get("id") if isinstance(entity, dict) else None

    if name in ("payment.captured", "order.paid") and isinstance(order_id, str) and isinstance(payment_id, str):
        payment = Payment.objects.filter(provider_order_id=order_id, provider="razorpay").first()
        if payment is not None:
            try:
                amount = int(entity.get("amount"))
            except (TypeError, ValueError):
                amount = -1
            if amount != payment.amount_paise:
                logger.error("Webhook amount mismatch for order %s: got %s, expected %s", order_id, amount, payment.amount_paise)
            else:
                fulfill(payment.pk, payment_id)
    elif name == "payment.failed" and isinstance(order_id, str):
        reason = str(entity.get("error_description") or "Payment failed")[:255]
        Payment.objects.filter(provider_order_id=order_id, status=Payment.Status.CREATED).update(failure_reason=reason)
    return JsonResponse({"ok": True})
