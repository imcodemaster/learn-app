from django.contrib import admin, messages

from core.utils import format_rupees

from .models import Payment


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ["created_at", "user", "description", "amount", "status", "provider", "provider_payment_id"]
    list_filter = ["status", "purpose", "provider"]
    search_fields = ["provider_order_id", "provider_payment_id", "receipt", "user__name", "user__email", "user__phone", "description"]
    list_select_related = ["user"]
    date_hierarchy = "created_at"
    readonly_fields = [
        "user", "purpose", "course", "booking", "description", "amount", "currency", "provider",
        "provider_order_id", "provider_payment_id", "receipt", "status", "failure_reason", "paid_at",
        "created_at", "updated_at",
    ]
    fields = readonly_fields + ["admin_note"]
    actions = ["mark_refunded", "mark_refund_due"]

    @admin.display(description="Amount", ordering="amount_paise")
    def amount(self, obj):
        return format_rupees(obj.amount_paise)

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False  # keep payment records for accounting

    @admin.action(description="Mark as refunded (after refunding in the Razorpay dashboard)")
    def mark_refunded(self, request, queryset):
        updated = queryset.filter(status__in=[Payment.Status.PAID, Payment.Status.REFUND_DUE]).update(
            status=Payment.Status.REFUNDED
        )
        self.message_user(request, f"Marked {updated} payment(s) as refunded.", messages.SUCCESS)

    @admin.action(description="Mark as refund due")
    def mark_refund_due(self, request, queryset):
        updated = queryset.filter(status=Payment.Status.PAID).update(status=Payment.Status.REFUND_DUE)
        self.message_user(request, f"Marked {updated} payment(s) as refund due.", messages.SUCCESS)
