from decimal import Decimal

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models


class Batch(models.Model):
    """A classroom batch at the study center, e.g. 'Python for Beginners, 4–6 PM'."""

    course = models.ForeignKey(
        "courses.Course", null=True, blank=True, on_delete=models.SET_NULL, related_name="batches",
        help_text="Optional: the online course on the same topic.",
    )
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True, default="")
    days_label = models.CharField("days", max_length=60, default="Mon–Sat")
    start_time = models.TimeField()
    end_time = models.TimeField()
    start_date = models.DateField()
    duration_label = models.CharField("duration", max_length=60, blank=True, default="2–3 months")
    total_seats = models.PositiveIntegerField(default=10, validators=[MinValueValidator(1), MaxValueValidator(200)])
    seats_per_row = models.PositiveIntegerField(
        "seats per row (seat map)", default=5, validators=[MinValueValidator(1), MaxValueValidator(20)]
    )
    fee = models.DecimalField(
        "course fee (₹)", max_digits=10, decimal_places=2, default=Decimal("0.00"),
        validators=[MinValueValidator(Decimal("0"))],
    )
    booking_amount = models.DecimalField(
        "pay online to book (₹)", max_digits=10, decimal_places=2, default=Decimal("0.00"),
        validators=[MinValueValidator(Decimal("0"))],
        help_text="Full fee, an advance, or 0 to reserve now and pay at the center.",
    )
    is_active = models.BooleanField("open for booking", default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["start_date", "start_time"]
        verbose_name_plural = "batches"

    def __str__(self) -> str:
        return f"{self.title} ({self.start_time:%H:%M}–{self.end_time:%H:%M})"

    def clean(self):
        if self.start_time and self.end_time and self.end_time <= self.start_time:
            raise ValidationError({"end_time": "End time must be after the start time."})
        if self.fee and self.booking_amount and self.booking_amount > self.fee:
            raise ValidationError({"booking_amount": "Booking amount can't be more than the course fee."})


class Shift(models.Model):
    """A self-study library shift with a monthly desk fee, e.g. 'Morning 10:00–14:00, ₹400/month'."""

    name = models.CharField(max_length=80)
    start_time = models.TimeField()
    end_time = models.TimeField()
    monthly_fee = models.DecimalField(
        "monthly fee (₹)", max_digits=10, decimal_places=2, validators=[MinValueValidator(Decimal("0"))]
    )
    is_active = models.BooleanField("open for booking", default=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "start_time"]
        verbose_name = "library shift"
        verbose_name_plural = "library shifts"

    def __str__(self) -> str:
        return f"{self.name} ({self.start_time:%H:%M}–{self.end_time:%H:%M})"

    def clean(self):
        if self.start_time and self.end_time and self.end_time <= self.start_time:
            raise ValidationError({"end_time": "End time must be after the start time."})


class Booking(models.Model):
    class Type(models.TextChoices):
        BATCH = "batch", "Course batch seat"
        LIBRARY = "library", "Library desk"

    class Status(models.TextChoices):
        HELD = "held", "Awaiting payment"
        CONFIRMED = "confirmed", "Confirmed"
        CANCELLED = "cancelled", "Cancelled"
        EXPIRED = "expired", "Expired"

    code = models.CharField(max_length=20, unique=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="bookings")
    booking_type = models.CharField("type", max_length=10, choices=Type.choices)
    batch = models.ForeignKey(Batch, null=True, blank=True, on_delete=models.PROTECT, related_name="bookings")
    shift = models.ForeignKey(Shift, null=True, blank=True, on_delete=models.PROTECT, related_name="bookings")
    seat_no = models.PositiveIntegerField("seat / desk number")
    period_start = models.DateField(null=True, blank=True)
    period_end = models.DateField(null=True, blank=True, help_text="Exclusive end date (library bookings).")
    months = models.PositiveSmallIntegerField(null=True, blank=True)
    amount_paise = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=12, choices=Status.choices, db_index=True)
    # 1 while the booking holds its seat (held/confirmed), NULL otherwise. Unique
    # constraints below then stop two active bookings for the same seat — even
    # on MySQL, which has no partial indexes (NULLs never clash).
    active_lock = models.PositiveSmallIntegerField(null=True, blank=True, editable=False)
    hold_expires_at = models.DateTimeField(null=True, blank=True)
    confirmed_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancel_reason = models.CharField(max_length=255, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["batch", "seat_no", "active_lock"], name="uq_booking_batch_seat_active"),
            models.UniqueConstraint(fields=["batch", "user", "active_lock"], name="uq_booking_batch_user_active"),
        ]
        indexes = [
            models.Index(fields=["shift", "seat_no"], name="booking_shift_seat_idx"),
            models.Index(fields=["user", "status"], name="booking_user_status_idx"),
        ]

    def __str__(self) -> str:
        return self.code
