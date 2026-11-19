import re

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers

from core.utils import normalize_indian_phone


def check_password_strength(value: str, user=None) -> str:
    if not re.search(r"[A-Za-z]", value) or not re.search(r"\d", value):
        raise serializers.ValidationError("Use both letters and numbers.")
    try:
        validate_password(value, user=user)
    except DjangoValidationError as exc:
        raise serializers.ValidationError(list(exc.messages)) from exc
    return value


class PhoneField(serializers.CharField):
    def __init__(self, **kwargs):
        kwargs.setdefault("max_length", 20)
        super().__init__(**kwargs)

    def to_internal_value(self, data):
        value = super().to_internal_value(data)
        phone = normalize_indian_phone(value)
        if phone is None:
            raise serializers.ValidationError("Enter a valid 10-digit Indian mobile number.")
        return phone


class LowercaseEmailField(serializers.EmailField):
    def __init__(self, **kwargs):
        kwargs.setdefault("max_length", 190)
        super().__init__(**kwargs)

    def to_internal_value(self, data):
        return super().to_internal_value(data).strip().lower()


class OtpCodeField(serializers.RegexField):
    def __init__(self, **kwargs):
        super().__init__(r"^[0-9]{6}$", max_length=6, min_length=6,
                         error_messages={"invalid": "Enter the 6-digit code."}, **kwargs)


class RegisterSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120)
    email = LowercaseEmailField()
    password = serializers.CharField(max_length=128, trim_whitespace=False)

    def validate(self, attrs):
        from .models import User

        candidate = User(name=attrs.get("name", ""), email=attrs.get("email"))
        try:
            check_password_strength(attrs["password"], candidate)
        except serializers.ValidationError as exc:
            raise serializers.ValidationError({"password": exc.detail}) from exc
        return attrs


class LoginSerializer(serializers.Serializer):
    email = LowercaseEmailField()
    password = serializers.CharField(max_length=128, trim_whitespace=False)


class OtpSendSerializer(serializers.Serializer):
    phone = PhoneField()


class OtpVerifySerializer(serializers.Serializer):
    phone = PhoneField()
    code = OtpCodeField()
    name = serializers.CharField(max_length=120, required=False, allow_blank=True, default="")


class GoogleLoginSerializer(serializers.Serializer):
    id_token = serializers.CharField(max_length=4096, trim_whitespace=True)


class ForgotPasswordSerializer(serializers.Serializer):
    email = LowercaseEmailField()


class ResetPasswordSerializer(serializers.Serializer):
    email = LowercaseEmailField()
    code = OtpCodeField()
    password = serializers.CharField(max_length=128, trim_whitespace=False)

    def validate_password(self, value):
        return check_password_strength(value)


class ProfileSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120, min_length=1)


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(max_length=128, trim_whitespace=False, required=False, allow_blank=True)
    new_password = serializers.CharField(max_length=128, trim_whitespace=False)


class DeleteAccountSerializer(serializers.Serializer):
    confirm = serializers.CharField(max_length=20)

    def validate_confirm(self, value):
        if value != "DELETE":
            raise serializers.ValidationError('Type DELETE to confirm.')
        return value
