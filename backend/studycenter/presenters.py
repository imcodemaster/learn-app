from datetime import timedelta

from core.models import SiteSettings
from core.utils import hhmm, iso_utc, seat_label, to_paise

from .models import Batch, Booking, Shift


def batch_summary(batch: Batch, seats_taken: int | None = None) -> dict:
    if seats_taken is None:
        seats_taken = Booking.objects.filter(batch=batch, active_lock=1).count()
    course = batch.course
    return {
        "id": batch.pk,
        "title": batch.title,
        "description": batch.description,
        "course": {"id": course.pk, "title": course.title, "slug": course.slug} if course else None,
        "days_label": batch.days_label,
        "start_time": hhmm(batch.start_time),
        "end_time": hhmm(batch.end_time),
        "start_date": batch.start_date.isoformat(),
        "duration_label": batch.duration_label,
        "total_seats": batch.total_seats,
        "seats_per_row": batch.seats_per_row,
        "seats_left": max(0, batch.total_seats - seats_taken),
        "fee_paise": to_paise(batch.fee),
        "booking_amount_paise": to_paise(batch.booking_amount),
        "is_active": batch.is_active,
    }


def shift_payload(shift: Shift) -> dict:
    return {
        "id": shift.pk,
        "name": shift.name,
        "start_time": hhmm(shift.start_time),
        "end_time": hhmm(shift.end_time),
        "monthly_fee_paise": to_paise(shift.monthly_fee),
    }


def booking_seat_label(booking: Booking, desks_per_row: int | None = None) -> str:
    if booking.booking_type == Booking.Type.BATCH and booking.batch_id:
        return seat_label(booking.seat_no, booking.batch.seats_per_row)
    per_row = desks_per_row if desks_per_row is not None else SiteSettings.load().library_desks_per_row
    return seat_label(booking.seat_no, per_row)


def booking_description(booking: Booking) -> str:
    label = booking_seat_label(booking)
    if booking.booking_type == Booking.Type.BATCH and booking.batch_id:
        batch = booking.batch
        return f"Seat {label} · {batch.title} ({batch.start_time:%H:%M}–{batch.end_time:%H:%M})"
    months = booking.months or 1
    start = f"{booking.period_start:%d %b %Y}" if booking.period_start else ""
    return f"Library desk {label} · {booking.shift.name} · {months} month{'s' if months > 1 else ''} from {start}"


def booking_payload(booking: Booking, desks_per_row: int | None = None) -> dict:
    is_batch = booking.booking_type == Booking.Type.BATCH
    return {
        "id": booking.pk,
        "code": booking.code,
        "type": booking.booking_type,
        "status": booking.status,
        "seat_no": booking.seat_no,
        "seat_label": booking_seat_label(booking, desks_per_row),
        "amount_paise": booking.amount_paise,
        "hold_expires_at": iso_utc(booking.hold_expires_at) if booking.status == Booking.Status.HELD else None,
        "period_start": booking.period_start.isoformat() if booking.period_start else None,
        "period_end": booking.period_end.isoformat() if booking.period_end else None,
        "valid_until": (booking.period_end - timedelta(days=1)).isoformat() if booking.period_end else None,
        "months": booking.months,
        "batch": batch_summary(booking.batch) if is_batch and booking.batch_id else None,
        "shift": shift_payload(booking.shift) if not is_batch and booking.shift_id else None,
        "description": booking_description(booking),
        "cancel_reason": booking.cancel_reason or None,
        "created_at": iso_utc(booking.created_at),
        "confirmed_at": iso_utc(booking.confirmed_at),
        "cancelled_at": iso_utc(booking.cancelled_at),
    }
