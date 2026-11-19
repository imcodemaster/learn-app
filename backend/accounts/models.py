from django.conf import settings
from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.contrib.auth.models import PermissionsMixin
from django.db import models
from django.utils import timezone


class UserManager(BaseUserManager):
    use_in_migrations = True

    def _create_user(self, email, password, **extra):
        email = self.normalize_email(email).strip().lower() if email else None
        user = self.model(email=email, **extra)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_user(self, email=None, password=None, **extra):
        extra.setdefault("is_staff", False)
        extra.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra)

    def create_superuser(self, email, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        extra.setdefault("email_verified", True)
        if not email:
            raise ValueError("An admin account needs an email address.")
        if extra.get("is_staff") is not True or extra.get("is_superuser") is not True:
            raise ValueError("Superusers must have is_staff=True and is_superuser=True.")
        return self._create_user(email, password, **extra)


class User(AbstractBaseUser, PermissionsMixin):
    """
    A student (or admin). Students can sign in with email + password, a mobile
    OTP, or Google — any of email / phone / Google may be missing.
    """

    name = models.CharField(max_length=120, blank=True, default="")
    email = models.EmailField(max_length=190, unique=True, null=True, blank=True)
    phone = models.CharField(max_length=20, unique=True, null=True, blank=True, help_text="Format: +91XXXXXXXXXX")
    google_sub = models.CharField("Google account ID", max_length=64, unique=True, null=True, blank=True, editable=False)
    avatar_url = models.URLField(max_length=500, blank=True, default="")
    email_verified = models.BooleanField(default=False)
    phone_verified = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True, help_text="Untick to block this account from signing in.")
    is_staff = models.BooleanField("admin panel access", default=False)
    date_joined = models.DateTimeField(default=timezone.now)
    deleted_at = models.DateTimeField(null=True, blank=True, editable=False)

    objects = UserManager()

    USERNAME_FIELD = "email"
    EMAIL_FIELD = "email"
    REQUIRED_FIELDS = ["name"]

    class Meta:
        ordering = ["-date_joined"]
        verbose_name = "user"
        verbose_name_plural = "users"

    def __str__(self) -> str:
        return self.name or self.email or self.phone or f"User #{self.pk}"

    def save(self, *args, **kwargs):
        # Missing unique values must be NULL (never ""), so many users can be
        # without an email or phone at the same time.
        self.email = (self.email or "").strip().lower() or None
        self.phone = (self.phone or "").strip() or None
        self.google_sub = self.google_sub or None
        super().save(*args, **kwargs)


class AuthToken(models.Model):
    """App session. Only a SHA-256 hash of the token is stored."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="auth_tokens")
    token_hash = models.CharField(max_length=64, unique=True, editable=False)
    created_at = models.DateTimeField(default=timezone.now)
    expires_at = models.DateTimeField()
    last_used_at = models.DateTimeField(default=timezone.now)
    user_agent = models.CharField(max_length=255, blank=True, default="")
    ip = models.GenericIPAddressField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "app session"
        verbose_name_plural = "app sessions"

    def __str__(self) -> str:
        return f"Session of {self.user} ({self.created_at:%d %b %Y})"


class OtpCode(models.Model):
    PURPOSE_LOGIN = "login"
    PURPOSE_RESET = "reset_password"

    purpose = models.CharField(max_length=20)
    destination = models.CharField(max_length=190)
    code_hash = models.CharField(max_length=64)
    attempts = models.PositiveSmallIntegerField(default=0)
    expires_at = models.DateTimeField()
    consumed_at = models.DateTimeField(null=True, blank=True)
    ip = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        indexes = [models.Index(fields=["destination", "purpose"], name="otp_dest_purpose_idx")]

    def __str__(self) -> str:
        return f"{self.purpose} code for {self.destination}"
