"""
Seat booking rules.

Race safety: every booking runs in a transaction that first locks the batch
row (or the overlapping library shift rows) with SELECT ... FOR UPDATE, so two
students tapping the same seat at the same moment are handled one after the
other. Unique constraints on (batch, seat, active_lock) are a second guard.

Unpaid seats are held for BOOKING_HOLD_MINUTES; stale holds expire lazily.
"""

from datetime import date, timedelta

from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Q
from django.utils import timezone

from core.api import ApiError, field_error, not_found
from core.models import SiteSettings
from core.utils import add_months, random_code, seat_label, times_overlap, to_paise

from .models import Batch, Booking, Shift


def expire_stale_holds() -> int:
    now = timezone.now()
    return Booking.objects.filter(status=Booking.Status.HELD, hold_expires_at__lt=now).update(
        status=Booking.Status.EXPIRED, active_lock=None, updated_at=now
    )


def new_booking_code(prefix: str) -> str:
    for _ in range(5):
        code = f"LC{prefix}-{random_code(6)}"
        if not Booking.objects.filter(code=code).exists():
            return code
    return f"LC{prefix}-{random_code(10)}"


def _seat_status(rows: list[dict], user_id) -> str:
    if not rows:
        return "available"
    if user_id is not None and any(r["user_id"] == user_id for r in rows):
        return "mine"
    if any(r["status"] == Booking.Status.CONFIRMED for r in rows):
        return "booked"
    return "held"


def _seat_map(active_rows, total: int, per_row: int, user) -> list[dict]:
    by_seat: dict[int, list[dict]] = {}
    for row in active_rows:
        by_seat.setdefault(row["seat_no"], []).append(row)
    user_id = user.pk if user is not None and user.is_authenticated else None
    return [
        {"no": n, "label": seat_label(n, per_row), "status": _seat_status(by_seat.get(n, []), user_id)}
        for n in range(1, total + 1)
    ]


# ---------------------------------------------------------------- batches

def batch_seat_map(batch: Batch, user=None) -> list[dict]:
    rows = Booking.objects.filter(batch=batch, active_lock=1).values("seat_no", "user_id", "status")
    return _seat_map(rows, batch.total_seats, batch.seats_per_row, user)


def _start_hold(booking: Booking, amount_paise: int) -> None:
    now = timezone.now()
    booking.amount_paise = amount_paise
    booking.active_lock = 1
    if amount_paise > 0:
        booking.status = Booking.Status.HELD
        booking.hold_expires_at = now + timedelta(minutes=settings.BOOKING_HOLD_MINUTES)
    else:
        booking.status = Booking.Status.CONFIRMED  # "reserve now, pay at the center"
        booking.confirmed_at = now


def hold_batch_seat(user, batch_id: int, seat_no: int) -> Booking:
    expire_stale_holds()
    with transaction.atomic():
        batch = Batch.objects.select_for_update().filter(pk=batch_id).first()
        if batch is None:
            raise not_found("Batch not found.")
        if not batch.is_active:
            raise ApiError(409, "batch_closed", "Bookings for this batch are closed.")
        if not 1 <= seat_no <= batch.total_seats:
            raise field_error("seat_no", "Choose a seat from the seat map.")
        label = seat_label(seat_no, batch.seats_per_row)
        if Booking.objects.filter(batch=batch, user=user, active_lock=1).exists():
            raise ApiError(409, "already_booked", "You already have a seat in this batch. See My bookings.")
        if Booking.objects.filter(batch=batch, seat_no=seat_no, active_lock=1).exists():
            raise ApiError(409, "seat_taken", f"Seat {label} was just taken. Please choose another seat.")
        booking = Booking(
            code=new_booking_code("B"),
            user=user,
            booking_type=Booking.Type.BATCH,
            batch=batch,
            seat_no=seat_no,
            period_start=batch.start_date,
        )
        _start_hold(booking, to_paise(batch.booking_amount))
        try:
            with transaction.atomic():
                booking.save()
        except IntegrityError as exc:
            raise ApiError(409, "seat_taken", f"Seat {label} was just taken. Please choose another seat.") from exc
    return booking


# ---------------------------------------------------------------- library

def overlapping_shift_ids(shift: Shift) -> list[int]:
    """Shifts whose hours overlap this one (e.g. 'Full day' overlaps 'Morning')."""
    return [
        s.pk for s in Shift.objects.all()
        if times_overlap(s.start_time, s.end_time, shift.start_time, shift.end_time)
    ]


def library_quote(shift_id: int, start: date, months: int, seat_no: int | None = None) -> dict:
    """Validates a library request and returns shift, dates and price."""
    site = SiteSettings.load()
    if not site.library_enabled:
        raise ApiError(409, "library_closed", "Library desk booking is not available right now.")
    shift = Shift.objects.filter(pk=shift_id, is_active=True).first()
    if shift is None:
        raise not_found("Shift not found.")
    today = timezone.localdate()
    if start < today:
        raise field_error("start_date", "The start date can't be in the past.")
    if start > today + timedelta(days=site.library_advance_days):
        raise field_error("start_date", f"You can book up to {site.library_advance_days} days ahead.")
    if not 1 <= months <= site.library_max_months:
        raise field_error("months", f"Choose between 1 and {site.library_max_months} months.")
    if seat_no is not None and not 1 <= seat_no <= site.library_total_desks:
        raise field_error("seat_no", "Choose a desk from the seat map.")
    end = add_months(start, months)
    return {
        "site": site,
        "shift": shift,
        "start": start,
        "end": end,
        "months": months,
        "amount_paise": to_paise(shift.monthly_fee) * months,
    }


def _library_conflicts(shift_ids: list[int], start: date, end: date):
    return Booking.objects.filter(
        booking_type=Booking.Type.LIBRARY,
        active_lock=1,
        shift_id__in=shift_ids,
        period_start__lt=end,
        period_end__gt=start,
    )


def library_seat_map(quote: dict, user=None) -> list[dict]:
    site = quote["site"]
    rows = _library_conflicts(overlapping_shift_ids(quote["shift"]), quote["start"], quote["end"]).values(
        "seat_no", "user_id", "status"
    )
    return _seat_map(rows, site.library_total_desks, site.library_desks_per_row, user)


def hold_library_desk(user, shift_id: int, start: date, months: int, seat_no: int) -> Booking:
    expire_stale_holds()
    quote = library_quote(shift_id, start, months, seat_no)
    shift = quote["shift"]
    label = seat_label(seat_no, quote["site"].library_desks_per_row)
    with transaction.atomic():
        ids = overlapping_shift_ids(shift)
        # Lock every overlapping shift row (in id order to avoid deadlocks).
        list(Shift.objects.select_for_update().filter(pk__in=ids).order_by("pk"))
        conflicts = _library_conflicts(ids, quote["start"], quote["end"])
        if conflicts.filter(user=user).exists():
            raise ApiError(409, "already_booked", "You already have a desk for these dates and hours. See My bookings.")
        if conflicts.filter(seat_no=seat_no).exists():
            raise ApiError(409, "seat_taken", f"Desk {label} is not free for these dates. Please choose another desk.")
        booking = Booking(
            code=new_booking_code("L"),
            user=user,
            booking_type=Booking.Type.LIBRARY,
            shift=shift,
            seat_no=seat_no,
            period_start=quote["start"],
            period_end=quote["end"],
            months=months,
        )
        _start_hold(booking, quote["amount_paise"])
        booking.save()
    return booking


# ---------------------------------------------------------------- confirm / cancel

def confirm_booking_after_payment(booking_id: int) -> bool:
    """
    Confirms a booking once it is paid (also used by the admin "confirm" action).
    If the hold had already expired, the seat is taken back only when it is
    still free; returns False when that is impossible (refund needed).
    Must run inside a transaction.
    """
    booking = Booking.objects.select_for_update().get(pk=booking_id)
    now = timezone.now()
    if booking.status == Booking.Status.CONFIRMED:
        return True
    if booking.status == Booking.Status.HELD:
        booking.status = Booking.Status.CONFIRMED
        booking.confirmed_at = now
        booking.hold_expires_at = None
        booking.save(update_fields=["status", "confirmed_at", "hold_expires_at", "updated_at"])
        return True

    # Expired or cancelled: get the seat back only if nobody else has it now.
    same_seat_or_user = Q(seat_no=booking.seat_no) | Q(user_id=booking.user_id)
    if booking.booking_type == Booking.Type.BATCH:
        list(Batch.objects.select_for_update().filter(pk=booking.batch_id))
        clash = Booking.objects.filter(batch_id=booking.batch_id, active_lock=1).filter(same_seat_or_user)
    else:
        ids = overlapping_shift_ids(booking.shift)
        list(Shift.objects.select_for_update().filter(pk__in=ids).order_by("pk"))
        clash = _library_conflicts(ids, booking.period_start, booking.period_end).filter(same_seat_or_user)
    if clash.exclude(pk=booking.pk).exists():
        return False
    booking.status = Booking.Status.CONFIRMED
    booking.active_lock = 1
    booking.confirmed_at = now
    booking.hold_expires_at = None
    booking.cancelled_at = None
    booking.cancel_reason = ""
    try:
        with transaction.atomic():
            booking.save()
    except IntegrityError:
        return False
    return True


def cancel_booking(booking: Booking, reason: str) -> None:
    now = timezone.now()
    Booking.objects.filter(pk=booking.pk, status__in=[Booking.Status.HELD, Booking.Status.CONFIRMED]).update(
        status=Booking.Status.CANCELLED, active_lock=None, cancelled_at=now, cancel_reason=reason[:255], updated_at=now
    )
    booking.refresh_from_db()
