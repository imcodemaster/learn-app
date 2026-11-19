from datetime import timedelta

from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from core.api import ApiError
from core.ratelimit import client_ip
from core.utils import hash_token, iso_utc, new_token, valid_ip_or_none

from .models import AuthToken, OtpCode, User


def assert_active(user: User) -> None:
    if not user.is_active or user.deleted_at is not None:
        raise ApiError(403, "account_disabled", "This account is disabled. Please contact LearnInCreation for help.")


def user_payload(user: User) -> dict:
    return {
        "id": user.pk,
        "name": user.name,
        "email": user.email,
        "phone": user.phone,
        "role": "admin" if user.is_staff else "student",
        "avatar_url": user.avatar_url or None,
        "has_password": user.has_usable_password(),
        "email_verified": user.email_verified,
        "phone_verified": user.phone_verified,
        "google_linked": user.google_sub is not None,
        "created_at": iso_utc(user.date_joined),
    }


def issue_token(user: User, request) -> dict:
    token = new_token()
    now = timezone.now()
    expires = now + timedelta(days=settings.APP_SESSION_DAYS)
    AuthToken.objects.create(
        user=user,
        token_hash=hash_token(token),
        expires_at=expires,
        last_used_at=now,
        created_at=now,
        user_agent=(request.META.get("HTTP_USER_AGENT") or "")[:255],
        ip=valid_ip_or_none(client_ip(request)),
    )
    User.objects.filter(pk=user.pk).update(last_login=now)
    return {"token": token, "expires_at": iso_utc(expires)}


def revoke_all_tokens(user: User, keep_token_id: int | None = None) -> None:
    tokens = AuthToken.objects.filter(user=user)
    if keep_token_id is not None:
        tokens = tokens.exclude(pk=keep_token_id)
    tokens.delete()


def login_with_phone(phone: str, name: str) -> tuple[User, bool]:
    user = User.objects.filter(phone=phone).first()
    if user is not None:
        assert_active(user)
        if not user.phone_verified:
            user.phone_verified = True
            user.save(update_fields=["phone_verified"])
        return user, False
    try:
        with transaction.atomic():
            user = User.objects.create_user(email=None, password=None, phone=phone, phone_verified=True, name=name[:120])
    except IntegrityError:
        user = User.objects.get(phone=phone)
        assert_active(user)
        return user, False
    return user, True


def login_with_google(claims: dict) -> tuple[User, bool]:
    sub = str(claims["sub"])
    email = str(claims.get("email") or "").strip().lower()
    if len(email) > 190 or "@" not in email:
        email = ""
    name = str(claims.get("name") or "").strip()[:120]
    picture = claims.get("picture")
    picture = picture if isinstance(picture, str) and picture.startswith("https://") and len(picture) <= 500 else ""

    user = User.objects.filter(google_sub=sub).first()
    if user is not None:
        assert_active(user)
        if not user.avatar_url and picture:
            user.avatar_url = picture
            user.save(update_fields=["avatar_url"])
        return user, False

    if email:
        user = User.objects.filter(email=email).first()
        if user is not None:
            assert_active(user)
            user.google_sub = sub
            if not user.email_verified:
                # Someone may have registered this email without owning it.
                # Google has now proven ownership, so drop the unproven password
                # and sign out every existing session (account pre-hijack defence).
                user.email_verified = True
                user.set_unusable_password()
                revoke_all_tokens(user)
            if not user.avatar_url and picture:
                user.avatar_url = picture
            if not user.name and name:
                user.name = name
            user.save()
            return user, False

    user = User.objects.create_user(
        email=email or None,
        password=None,
        name=name or "Student",
        email_verified=bool(email),
        google_sub=sub,
        avatar_url=picture,
    )
    return user, True


def delete_account(user: User) -> None:
    """Removes personal data. Payment records are kept (needed for accounts/tax)."""
    from courses.models import Bookmark, Enrollment, LessonProgress
    from studycenter.models import Booking

    now = timezone.now()
    with transaction.atomic():
        AuthToken.objects.filter(user=user).delete()
        Bookmark.objects.filter(user=user).delete()
        LessonProgress.objects.filter(user=user).delete()
        Enrollment.objects.filter(user=user).delete()
        Booking.objects.filter(user=user, status__in=[Booking.Status.HELD, Booking.Status.CONFIRMED]).update(
            status=Booking.Status.CANCELLED, active_lock=None, cancelled_at=now,
            cancel_reason="Account deleted", updated_at=now,
        )
        for destination in (user.email, user.phone):
            if destination:
                OtpCode.objects.filter(destination=destination).delete()
        user.name = "Deleted user"
        user.email = None
        user.phone = None
        user.google_sub = None
        user.avatar_url = ""
        user.is_active = False
        user.deleted_at = now
        user.set_unusable_password()
        user.save()
