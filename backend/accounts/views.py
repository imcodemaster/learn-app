import logging

from django.conf import settings
from django.contrib.auth.hashers import make_password
from django.core.mail import send_mail
from django.db import IntegrityError, transaction
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated

from core import ratelimit
from core.api import ApiError, ok
from core.ratelimit import client_ip
from core.utils import valid_ip_or_none

from . import otp
from .google import GoogleTokenError, verify_google_id_token
from .models import AuthToken, OtpCode, User
from .serializers import (
    ChangePasswordSerializer,
    DeleteAccountSerializer,
    ForgotPasswordSerializer,
    GoogleLoginSerializer,
    LoginSerializer,
    OtpSendSerializer,
    OtpVerifySerializer,
    ProfileSerializer,
    RegisterSerializer,
    ResetPasswordSerializer,
    check_password_strength,
)
from .services import (
    assert_active,
    delete_account,
    issue_token,
    login_with_google,
    login_with_phone,
    revoke_all_tokens,
    user_payload,
)
from .sms import SmsError, send_otp_sms

logger = logging.getLogger("learnincreation")

EMAIL_TAKEN = "An account with this email already exists. Sign in instead, or use “Forgot password”."
BAD_LOGIN = "Incorrect email or password."


def _signed_in(user: User, request, status_code: int = 200, is_new: bool = False):
    session = issue_token(user, request)
    return ok(
        {"token": session["token"], "expires_at": session["expires_at"], "user": user_payload(user), "is_new": is_new},
        status_code,
    )


@api_view(["POST"])
@permission_classes([AllowAny])
def register(request):
    ratelimit.hit(f"register:ip:{client_ip(request)}", 10, 3600)
    serializer = RegisterSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    if User.objects.filter(email=data["email"]).exists():
        raise ApiError(409, "email_taken", EMAIL_TAKEN)
    try:
        with transaction.atomic():
            user = User.objects.create_user(email=data["email"], password=data["password"], name=data["name"])
    except IntegrityError as exc:
        raise ApiError(409, "email_taken", EMAIL_TAKEN) from exc
    return _signed_in(user, request, 201, True)


@api_view(["POST"])
@permission_classes([AllowAny])
def login(request):
    ratelimit.hit(f"login:ip:{client_ip(request)}", 20, 900)
    serializer = LoginSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data["email"]
    password = serializer.validated_data["password"]
    ratelimit.hit(f"login:email:{email}", 10, 900, "Too many sign-in attempts. Please wait 15 minutes.")
    user = User.objects.filter(email=email, deleted_at__isnull=True).first()
    if user is None or not user.has_usable_password():
        make_password(password)  # same amount of work as a real check (timing)
        raise ApiError(401, "invalid_credentials", BAD_LOGIN)
    if not user.check_password(password):
        raise ApiError(401, "invalid_credentials", BAD_LOGIN)
    assert_active(user)
    return _signed_in(user, request)


@api_view(["POST"])
@permission_classes([AllowAny])
def otp_send(request):
    ip = client_ip(request)
    ratelimit.hit(f"otp-send:ip:{ip}", 20, 3600)
    serializer = OtpSendSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    phone = serializer.validated_data["phone"]
    ratelimit.hit(f"otp-send:phone:{phone}", 5, 3600, "Too many codes requested for this number. Please try again later.")
    existing = User.objects.filter(phone=phone).first()
    if existing is not None:
        assert_active(existing)
    code = otp.issue(OtpCode.PURPOSE_LOGIN, phone, settings.OTP_TTL_SECONDS, valid_ip_or_none(ip))
    try:
        send_otp_sms(phone, code)
    except SmsError as exc:
        otp.discard(OtpCode.PURPOSE_LOGIN, phone)
        logger.error("Could not send OTP SMS: %s", exc)
        raise ApiError(502, "sms_failed", "We couldn't send the code right now. Please try again in a minute.") from exc
    data = {
        "sent": True,
        "phone": phone,
        "expires_in": settings.OTP_TTL_SECONDS,
        "resend_in": settings.OTP_RESEND_SECONDS,
    }
    if settings.SMS_BACKEND == "console" and settings.APP_ENV != "production":
        data["debug_code"] = code  # testing only: lets you sign in without an SMS provider
    return ok(data)


@api_view(["POST"])
@permission_classes([AllowAny])
def otp_verify(request):
    ratelimit.hit(f"otp-verify:ip:{client_ip(request)}", 30, 900)
    serializer = OtpVerifySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    phone = serializer.validated_data["phone"]
    ratelimit.hit(f"otp-verify:phone:{phone}", 10, 900)
    otp.verify(OtpCode.PURPOSE_LOGIN, phone, serializer.validated_data["code"])
    user, is_new = login_with_phone(phone, serializer.validated_data.get("name") or "")
    return _signed_in(user, request, 200, is_new)


@api_view(["POST"])
@permission_classes([AllowAny])
def google_login(request):
    ratelimit.hit(f"google:ip:{client_ip(request)}", 30, 900)
    serializer = GoogleLoginSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    if not settings.GOOGLE_CLIENT_IDS:
        raise ApiError(503, "google_not_configured", "Google sign-in is not set up on the server yet.")
    try:
        claims = verify_google_id_token(serializer.validated_data["id_token"], settings.GOOGLE_CLIENT_IDS)
    except GoogleTokenError as exc:
        logger.info("Rejected Google token: %s", exc)
        raise ApiError(401, "invalid_google_token", "Google sign-in failed. Please try again.") from exc
    user, is_new = login_with_google(claims)
    return _signed_in(user, request, 200, is_new)


@api_view(["POST"])
@permission_classes([AllowAny])
def forgot_password(request):
    ip = client_ip(request)
    ratelimit.hit(f"forgot:ip:{ip}", 20, 3600)
    serializer = ForgotPasswordSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data["email"]
    ratelimit.hit(f"forgot:email:{email}", 5, 3600)
    user = User.objects.filter(email=email, deleted_at__isnull=True, is_active=True).first()
    if user is not None:
        try:
            code = otp.issue(OtpCode.PURPOSE_RESET, email, settings.OTP_EMAIL_TTL_SECONDS, valid_ip_or_none(ip))
            minutes = settings.OTP_EMAIL_TTL_SECONDS // 60
            send_mail(
                "Your LearnInCreation password reset code",
                f"Hi {user.name or 'there'},\n\nYour password reset code is {code}. "
                f"It expires in {minutes} minutes.\n\nIf you didn't ask for this, you can ignore this email.\n\n"
                "— LearnInCreation",
                None,
                [email],
                fail_silently=False,
            )
        except ApiError:
            pass  # resend cooldown: answer the same way so emails can't be probed
        except Exception:  # noqa: BLE001 - mail server problems must not reveal anything
            logger.exception("Could not send password reset email")
    # Same answer whether or not the email exists (no account enumeration).
    return ok({"sent": True, "message": "If an account exists for this email, we've sent a 6-digit code to it."})


@api_view(["POST"])
@permission_classes([AllowAny])
def reset_password(request):
    ratelimit.hit(f"reset:ip:{client_ip(request)}", 20, 900)
    serializer = ResetPasswordSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data["email"]
    ratelimit.hit(f"reset:email:{email}", 10, 900)
    otp.verify(OtpCode.PURPOSE_RESET, email, serializer.validated_data["code"])
    user = User.objects.filter(email=email, deleted_at__isnull=True).first()
    if user is None:
        raise ApiError(422, "invalid_code", otp.INVALID_CODE, fields={"code": otp.INVALID_CODE})
    assert_active(user)
    user.set_password(serializer.validated_data["password"])
    user.email_verified = True
    user.save(update_fields=["password", "email_verified"])
    revoke_all_tokens(user)
    return _signed_in(user, request)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout(request):
    if isinstance(request.auth, AuthToken):
        request.auth.delete()
    return ok({"signed_out": True})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout_all(request):
    revoke_all_tokens(request.user)
    return ok({"signed_out": True})


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def me(request):
    user = request.user
    if request.method == "PATCH":
        serializer = ProfileSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user.name = serializer.validated_data["name"]
        user.save(update_fields=["name"])
    return ok(user_payload(user))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def change_password(request):
    user = request.user
    serializer = ChangePasswordSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    if user.has_usable_password():
        current = serializer.validated_data.get("current_password") or ""
        if not user.check_password(current):
            raise ApiError(422, "validation_error", "Current password is incorrect.",
                           fields={"current_password": "Current password is incorrect."})
    try:
        check_password_strength(serializer.validated_data["new_password"], user)
    except Exception as exc:  # serializers.ValidationError
        detail = getattr(exc, "detail", ["Choose a stronger password."])
        message = detail[0] if isinstance(detail, list) and detail else str(detail)
        raise ApiError(422, "validation_error", str(message), fields={"new_password": str(message)}) from exc
    user.set_password(serializer.validated_data["new_password"])
    user.save(update_fields=["password"])
    keep = request.auth.pk if isinstance(request.auth, AuthToken) else None
    revoke_all_tokens(user, keep_token_id=keep)  # sign out other devices
    return ok(user_payload(user))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def delete_me(request):
    serializer = DeleteAccountSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    if request.user.is_staff:
        raise ApiError(409, "admin_account", "Admin accounts can't be deleted from the app.")
    delete_account(request.user)
    return ok({"deleted": True})
