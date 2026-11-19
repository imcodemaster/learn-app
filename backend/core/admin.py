from django.contrib import admin
from django.shortcuts import redirect
from django.urls import reverse

from .models import Faq, SiteSettings


@admin.register(SiteSettings)
class SiteSettingsAdmin(admin.ModelAdmin):
    fieldsets = (
        ("Organisation", {"fields": ("org_name", "tagline", "hero_title", "about")}),
        ("Contact details", {"fields": ("phone", "email", "address", "hours", "website")}),
        ("Links", {"fields": ("youtube_url", "instagram_url", "linkedin_url", "privacy_url", "terms_url")}),
        ("Study center", {"fields": ("center_name", "center_address", "center_hours")}),
        (
            "Library desk booking",
            {
                "fields": (
                    "library_enabled",
                    "library_total_desks",
                    "library_desks_per_row",
                    "library_max_months",
                    "library_advance_days",
                ),
                "description": "Library shifts and monthly fees are managed under Study center → Library shifts.",
            },
        ),
    )

    def has_add_permission(self, request):
        return not SiteSettings.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False

    def changelist_view(self, request, extra_context=None):
        settings_row = SiteSettings.load()
        return redirect(reverse("admin:core_sitesettings_change", args=[settings_row.pk]))


@admin.register(Faq)
class FaqAdmin(admin.ModelAdmin):
    list_display = ("question", "sort_order", "is_active")
    list_editable = ("sort_order", "is_active")
    search_fields = ("question", "answer")
