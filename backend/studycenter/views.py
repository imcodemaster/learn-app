from datetime import timedelta

from django.conf import settings
from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import serializers
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated

from core import ratelimit
from core.api import ApiError, not_found, ok
from core.models import SiteSettings
from payments.models import Payment
from payments.services import checkout_payload, create_order

from .models import Batch, Booking, Shift
from .presenters import batch_summary, booking_description, booking_payload, shift_payload
from .services import (
    batch_seat_map,
    cancel_booking,
    expire_stale_holds,
    hold_batch_seat,
    hold_library_desk,
    library_quote,
    library_seat_map,
)


class BookBatchSerializer(serializers.Serializer):
    seat_no = serializers.IntegerField(min_value=1, max_value=10_000)


class LibraryQuerySerializer(serializers.Serializer):
    shift_id = serializers.IntegerField(min_value=1)
    start_date = serializers.DateField()
    months = serializers.IntegerField(min_value=1, max_value=12)


class LibraryBookSerializer(LibraryQuerySerializer):
    seat_no = serializers.IntegerField(min_value=1, max_value=10_000)


def _user(request):
    return request.user if request.user.is_authenticated else None


@api_view(["GET"])
def info(request):
    site = SiteSettings.load()
    return ok({
        "name": site.center_name,
        "address": site.center_address,
        "hours": site.center_hours,
        "phone": site.phone,
        "email": site.email,
        "hold_minutes": settings.BOOKING_HOLD_MINUTES,
        "library": {
            "enabled": site.library_enabled,
            "total_desks": site.library_total_desks,
            "desks_per_row": site.library_desks_per_row,
            "max_months": site.library_max_months,
            "advance_days": site.library_advance_days,
        },
        "shifts": [shift_payload(s) for s in Shift.objects.filter(is_active=True)],
    })


@api_view(["GET"])
def batches(request):
    expire_stale_holds()
    queryset = (
        Batch.objects.filter(is_active=True)
        .select_related("course")
        .annotate(taken=Count("bookings", filter=Q(bookings__active_lock=1)))
        .order_by("start_date", "start_time")
    )
    return ok([batch_summary(b, b.taken) for b in queryset])


@api_view(["GET"])
def batch_detail(request, batch_id):
    expire_stale_holds()
    batch = Batch.objects.select_related("course").filter(pk=batch_id).first()
    if batch is None:
        raise not_found("Batch not found.")
    user = _user(request)
    seats = batch_seat_map(batch, user)
    data = batch_summary(batch, sum(1 for seat in seats if seat["status"] != "available"))
    mine = Booking.objects.filter(batch=batch, user=user, active_lock=1).first() if user else None
    data["seats"] = seats
    data["my_booking"] = booking_payload(mine) if mine else None
    return ok(data)


def _booking_created(request, booking: Booking):
    """Returns the booking, plus Razorpay checkout details when payment is due."""
    if booking.status == Booking.Status.CONFIRMED:
        return ok({"booking": booking_payload(booking), "checkout": None}, 201)
    try:
        payment = create_order(
            request.user,
            purpose=Payment.Purpose.BOOKING,
            amount_paise=booking.amount_paise,
            description=booking_description(booking),
            booking=booking,
        )
    except ApiError:
        cancel_booking(booking, "Payment could not be started")  # free the seat again
        raise
    remaining = int((booking.hold_expires_at - timezone.now()).total_seconds())
    return ok(
        {
            "booking": booking_payload(booking),
            "checkout": checkout_payload(payment, request.user, timeout_seconds=max(60, remaining - 15)),
        },
        201,
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def book_batch(request, batch_id):
    ratelimit.hit(f"book:user:{request.user.pk}", 20, 3600)
    serializer = BookBatchSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    booking = hold_batch_seat(request.user, batch_id, serializer.validated_data["seat_no"])
    return _booking_created(request, booking)


@api_view(["GET"])
def library_availability(request):
    serializer = LibraryQuerySerializer(data=request.query_params)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    expire_stale_holds()
    quote = library_quote(data["shift_id"], data["start_date"], data["months"])
    end = quote["end"]
    return ok({
        "shift": shift_payload(quote["shift"]),
        "start_date": quote["start"].isoformat(),
        "end_date": end.isoformat(),
        "valid_until": (end - timedelta(days=1)).isoformat(),
        "months": quote["months"],
        "amount_paise": quote["amount_paise"],
        "desks_per_row": quote["site"].library_desks_per_row,
        "seats": library_seat_map(quote, _user(request)),
    })


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def book_library(request):
    ratelimit.hit(f"book:user:{request.user.pk}", 20, 3600)
    serializer = LibraryBookSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    booking = hold_library_desk(request.user, data["shift_id"], data["start_date"], data["months"], data["seat_no"])
    return _booking_created(request, booking)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_bookings(request):
    expire_stale_holds()
    site = SiteSettings.load()
    bookings = (
        Booking.objects.filter(user=request.user)
        .select_related("batch", "batch__course", "shift")
        .order_by("-created_at")[:100]
    )
    return ok([booking_payload(b, site.library_desks_per_row) for b in bookings])


def _own_booking(request, booking_id) -> Booking:
    booking = (
        Booking.objects.select_related("batch", "batch__course", "shift")
        .filter(pk=booking_id, user=request.user)  # students only ever see their own bookings
        .first()
    )
    if booking is None:
        raise not_found("Booking not found.")
    return booking


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_booking(request, booking_id):
    expire_stale_holds()
    return ok(booking_payload(_own_booking(request, booking_id)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def cancel_my_booking(request, booking_id):
    expire_stale_holds()
    booking = _own_booking(request, booking_id)
    if booking.status != Booking.Status.HELD:
        raise ApiError(
            409, "cannot_cancel",
            "Only bookings that are still awaiting payment can be cancelled in the app. "
            "For confirmed bookings, please contact the study center.",
        )
    cancel_booking(booking, "Cancelled by student")
    return ok(booking_payload(booking))
