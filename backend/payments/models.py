from django.conf import settings
from django.db import models

from core.utils import format_rupees


class Payment(models.Model):
    class Purpose(models.TextChoices):
        COURSE = "course", "Course purchase"
        BOOKING = "booking", "Study center booking"

    class Status(models.TextChoices):
        CREATED = "created", "Awaiting payment"
        PAID = "paid", "Paid"
        FAILED = "failed", "Failed"
        REFUND_DUE = "refund_due", "Refund due"
        REFUNDED = "refunded", "Refunded"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="payments")
    purpose = models.CharField(max_length=20, choices=Purpose.choices)
    course = models.ForeignKey("courses.Course", null=True, blank=True, on_delete=models.SET_NULL, related_name="payments")
    booking = models.ForeignKey("studycenter.Booking", null=True, blank=True, on_delete=models.SET_NULL, related_name="payments")
    description = models.CharField(max_length=255)
    amount_paise = models.PositiveIntegerField()
    currency = models.CharField(max_length=3, default="INR")
    provider = models.CharField(max_length=20, default="razorpay")
    provider_order_id = models.CharField("order ID", max_length=64, unique=True)
    provider_payment_id = models.CharField("payment ID", max_length=64, unique=True, null=True, blank=True)
    receipt = models.CharField(max_length=40, unique=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.CREATED, db_index=True)
    failure_reason = models.CharField(max_length=255, blank=True, default="")
    admin_note = models.CharField(max_length=255, blank=True, default="")
    paid_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.description} — {format_rupees(self.amount_paise)} ({self.get_status_display()})"
