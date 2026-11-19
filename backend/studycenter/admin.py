from datetime import timedelta

from django.contrib import admin, messages
from django.db import transaction
from django.db.models import Count, Q
from django.urls import reverse
from django.utils import timezone
from django.utils.html import format_html, format_html_join

from core.models import SiteSettings
from core.utils import format_rupees, seat_label, to_paise
from payments.models import Payment

from .models import Batch, Booking, Shift
from .presenters import booking_seat_label
from .services import cancel_booking, confirm_booking_after_payment, expire_stale_holds, overlapping_shift_ids


def _render_seat_map(total: int, per_row: int, bookings_by_seat: dict) -> str:
    cells = []
    for n in range(1, total + 1):
        booking = bookings_by_seat.get(n)
        if booking is None:
            css, who = "li-seat-free", ""
        else:
            css = "li-seat-booked" if booking.status == Booking.Status.CONFIRMED else "li-seat-held"
            who = booking.user.name or booking.user.phone or booking.user.email or ""
        cells.append((css, seat_label(n, per_row), who))
    grid = format_html_join("", '<div class="li-seat {}">{}<small>{}</small></div>', cells)
    return format_html(
        '<div class="li-seat-map" style="grid-template-columns: repeat({}, minmax(52px, auto))">{}</div>'
        '<div class="li-seat-legend">Green = free · Amber = awaiting payment · Blue = confirmed</div>',
        per_row,
        grid,
    )


@admin.register(Batch)
class BatchAdmin(admin.ModelAdmin):
    list_display = ["title", "timing", "start_date", "seats", "fee_display", "booking_amount_display", "is_active"]
    list_editable = ["is_active"]
    list_filter = ["is_active", "course"]
    search_fields = ["title", "description"]
    autocomplete_fields = ["course"]
    readonly_fields = ["seat_map", "bookings_link"]
    fieldsets = [
        (None, {"fields": ["title", "course", "description"]}),
        ("Schedule", {"fields": ["days_label", "start_time", "end_time", "start_date", "duration_label"]}),
        ("Seats & fees", {"fields": ["total_seats", "seats_per_row", "fee", "booking_amount", "is_active"]}),
        ("Who is sitting where", {"fields": ["seat_map", "bookings_link"]}),
    ]

    def get_queryset(self, request):
        return super().get_queryset(request).annotate(_taken=Count("bookings", filter=Q(bookings__active_lock=1)))

    def changelist_view(self, request, extra_context=None):
        expire_stale_holds()
        return super().changelist_view(request, extra_context)

    @admin.display(description="Timing")
    def timing(self, obj):
        return f"{obj.days_label}, {obj.start_time:%H:%M}–{obj.end_time:%H:%M}"

    @admin.display(description="Seats booked", ordering="_taken")
    def seats(self, obj):
        return f"{obj._taken} / {obj.total_seats}"

    @admin.display(description="Fee", ordering="fee")
    def fee_display(self, obj):
        return format_rupees(to_paise(obj.fee))

    @admin.display(description="Pay to book", ordering="booking_amount")
    def booking_amount_display(self, obj):
        amount = to_paise(obj.booking_amount)
        return format_rupees(amount) if amount else "Pay at center"

    @admin.display(description="Seat map")
    def seat_map(self, obj):
        if not obj or not obj.pk:
            return "Save the batch to see its seat map."
        expire_stale_holds()
        active = {
            b.seat_no: b for b in Booking.objects.filter(batch=obj, active_lock=1).select_related("user")
        }
        return _render_seat_map(obj.total_seats, obj.seats_per_row, active)

    @admin.display(description="Bookings")
    def bookings_link(self, obj):
        if not obj or not obj.pk:
            return "-"
        url = reverse("admin:studycenter_booking_changelist") + f"?batch__id__exact={obj.pk}"
        return format_html('<a href="{}">See all bookings for this batch</a>', url)


@admin.register(Shift)
class ShiftAdmin(admin.ModelAdmin):
    list_display = ["name", "timing", "fee_display", "is_active", "sort_order"]
    list_editable = ["is_active", "sort_order"]
    readonly_fields = ["desk_map_today"]
    fields = ["name", "start_time", "end_time", "monthly_fee", "is_active", "sort_order", "desk_map_today"]

    @admin.display(description="Timing")
    def timing(self, obj):
        return f"{obj.start_time:%H:%M}–{obj.end_time:%H:%M}"

    @admin.display(description="Monthly fee", ordering="monthly_fee")
    def fee_display(self, obj):
        return format_rupees(to_paise(obj.monthly_fee))

    @admin.display(description="Desks taken today (this shift and overlapping shifts)")
    def desk_map_today(self, obj):
        if not obj or not obj.pk:
            return "Save the shift to see the desk map."
        expire_stale_holds()
        site = SiteSettings.load()
        today = timezone.localdate()
        rows = Booking.objects.filter(
            booking_type=Booking.Type.LIBRARY,
            active_lock=1,
            shift_id__in=overlapping_shift_ids(obj),
            period_start__lte=today,
            period_end__gt=today,
        ).select_related("user")
        by_seat = {}
        for booking in rows:
            by_seat.setdefault(booking.seat_no, booking)
        return _render_seat_map(site.library_total_desks, site.library_desks_per_row, by_seat)


@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display = ["code", "user", "booking_type", "what", "seat", "period", "amount", "status", "created_at"]
    list_filter = ["status", "booking_type", "batch", "shift"]
    search_fields = ["code", "user__name", "user__email", "user__phone"]
    list_select_related = ["user", "batch", "shift"]
    date_hierarchy = "created_at"
    readonly_fields = [
        "code", "user", "booking_type", "batch", "shift", "seat", "period_start", "period_end", "months",
        "amount", "status", "hold_expires_at", "confirmed_at", "cancelled_at", "created_at", "payments_list",
    ]
    fields = readonly_fields + ["cancel_reason"]
    actions = ["confirm_bookings", "cancel_bookings", "cancel_and_refund"]

    def has_add_permission(self, request):
        return False  # students book from the app

    def has_delete_permission(self, request, obj=None):
        return False  # cancel instead, so history is kept

    def changelist_view(self, request, extra_context=None):
        expire_stale_holds()
        return super().changelist_view(request, extra_context)

    @admin.display(description="Batch / shift")
    def what(self, obj):
        if obj.batch_id:
            return obj.batch.title
        return obj.shift.name if obj.shift_id else "-"

    @admin.display(description="Seat")
    def seat(self, obj):
        return booking_seat_label(obj)

    @admin.display(description="Period")
    def period(self, obj):
        if obj.booking_type == Booking.Type.LIBRARY and obj.period_start and obj.period_end:
            last_day = obj.period_end - timedelta(days=1)
            return f"{obj.period_start:%d %b} – {last_day:%d %b %Y}"
        return f"From {obj.period_start:%d %b %Y}" if obj.period_start else "-"

    @admin.display(description="Amount", ordering="amount_paise")
    def amount(self, obj):
        return format_rupees(obj.amount_paise) if obj.amount_paise else "Pay at center"

    @admin.display(description="Payments")
    def payments_list(self, obj):
        rows = [(p.created_at.strftime("%d %b %Y %H:%M"), format_rupees(p.amount_paise), p.get_status_display(),
                 p.provider_payment_id or p.provider_order_id) for p in obj.payments.all()]
        if not rows:
            return "No payments"
        return format_html_join("", "<div>{} · {} · {} · {}</div>", rows)

    @admin.action(description="Confirm selected bookings (e.g. paid at the center)")
    def confirm_bookings(self, request, queryset):
        done = failed = 0
        for booking in queryset:
            with transaction.atomic():
                if confirm_booking_after_payment(booking.pk):
                    done += 1
                else:
                    failed += 1
        if done:
            self.message_user(request, f"Confirmed {done} booking(s).", messages.SUCCESS)
        if failed:
            self.message_user(request, f"{failed} booking(s) could not be confirmed because the seat is taken now.",
                              messages.WARNING)

    @admin.action(description="Cancel selected bookings and free the seats")
    def cancel_bookings(self, request, queryset):
        count = 0
        for booking in queryset.filter(status__in=[Booking.Status.HELD, Booking.Status.CONFIRMED]):
            cancel_booking(booking, "Cancelled by the study center")
            count += 1
        self.message_user(request, f"Cancelled {count} booking(s).", messages.SUCCESS)

    @admin.action(description="Cancel, free the seats and mark payments as refund due")
    def cancel_and_refund(self, request, queryset):
        count = 0
        for booking in queryset.filter(status__in=[Booking.Status.HELD, Booking.Status.CONFIRMED]):
            cancel_booking(booking, "Cancelled by the study center (refund due)")
            Payment.objects.filter(booking=booking, status=Payment.Status.PAID).update(
                status=Payment.Status.REFUND_DUE, admin_note="Booking cancelled by admin"
            )
            count += 1
        self.message_user(
            request, f"Cancelled {count} booking(s). Refund them in the Razorpay dashboard, then mark them refunded under Payments.",
            messages.SUCCESS,
        )
