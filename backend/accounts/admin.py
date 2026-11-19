from django import forms
from django.contrib import admin, messages
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import ReadOnlyPasswordHashField
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError

from core.utils import normalize_indian_phone

from .models import AuthToken, User


def _clean_phone(value: str | None) -> str | None:
    if not value:
        return None
    phone = normalize_indian_phone(value)
    if phone is None:
        raise ValidationError("Enter a valid 10-digit Indian mobile number.")
    return phone


class UserCreationForm(forms.ModelForm):
    password1 = forms.CharField(label="Password", widget=forms.PasswordInput, strip=False)
    password2 = forms.CharField(label="Password confirmation", widget=forms.PasswordInput, strip=False)

    class Meta:
        model = User
        fields = ["email", "name", "phone"]

    def clean_phone(self):
        return _clean_phone(self.cleaned_data.get("phone"))

    def clean_password2(self):
        password1 = self.cleaned_data.get("password1")
        password2 = self.cleaned_data.get("password2")
        if password1 and password2 and password1 != password2:
            raise ValidationError("The two passwords don't match.")
        if password2:
            validate_password(password2)
        return password2

    def save(self, commit=True):
        user = super().save(commit=False)
        user.set_password(self.cleaned_data["password1"])
        if commit:
            user.save()
        return user


class UserChangeForm(forms.ModelForm):
    password = ReadOnlyPasswordHashField(
        help_text="Passwords are stored securely and can't be viewed. Use the button to set a new one."
    )

    class Meta:
        model = User
        fields = [
            "email", "password", "name", "phone", "avatar_url", "email_verified", "phone_verified",
            "is_active", "is_staff", "is_superuser", "groups", "user_permissions",
        ]

    def clean_phone(self):
        return _clean_phone(self.cleaned_data.get("phone"))


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    form = UserChangeForm
    add_form = UserCreationForm
    list_display = ["__str__", "email", "phone", "is_active", "is_staff", "date_joined", "last_login"]
    list_filter = ["is_active", "is_staff", "email_verified", "phone_verified"]
    search_fields = ["name", "email", "phone"]
    ordering = ["-date_joined"]
    readonly_fields = ["date_joined", "last_login", "google_linked", "deleted_at"]
    filter_horizontal = ["groups", "user_permissions"]
    fieldsets = [
        (None, {"fields": ["name", "email", "phone", "password"]}),
        ("Status", {"fields": ["is_active", "email_verified", "phone_verified", "google_linked", "avatar_url"]}),
        ("Admin panel access", {
            "classes": ["collapse"],
            "fields": ["is_staff", "is_superuser", "groups", "user_permissions"],
        }),
        ("Dates", {"fields": ["date_joined", "last_login", "deleted_at"]}),
    ]
    add_fieldsets = [
        (None, {"classes": ["wide"], "fields": ["email", "name", "phone", "password1", "password2"]}),
    ]
    actions = ["sign_out_everywhere"]

    @admin.display(boolean=True, description="Google linked")
    def google_linked(self, obj):
        return obj.google_sub is not None

    @admin.action(description="Sign selected users out of the app on all devices")
    def sign_out_everywhere(self, request, queryset):
        count, _ = AuthToken.objects.filter(user__in=queryset).delete()
        self.message_user(request, f"Ended {count} app session(s).", messages.SUCCESS)

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        if change and not obj.is_active:
            AuthToken.objects.filter(user=obj).delete()  # blocked users are signed out at once


@admin.register(AuthToken)
class AuthTokenAdmin(admin.ModelAdmin):
    list_display = ["user", "created_at", "last_used_at", "expires_at", "ip", "user_agent"]
    search_fields = ["user__name", "user__email", "user__phone"]
    list_select_related = ["user"]
    readonly_fields = ["user", "created_at", "last_used_at", "expires_at", "ip", "user_agent"]
    exclude = ["token_hash"]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False
