import secrets
from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone
from django.utils.text import slugify

from core.utils import reading_minutes, to_paise


def _unique_slug(model, base: str, instance_pk) -> str:
    base = (slugify(base) or "item")[:200]
    slug = base
    counter = 2
    while model.objects.filter(slug=slug).exclude(pk=instance_pk).exists():
        slug = f"{base}-{counter}"
        counter += 1
    return slug


def thumbnail_path(instance, filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "jpg"
    return f"courses/thumbnails/{secrets.token_hex(16)}.{ext}"


def lesson_image_path(instance, filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "jpg"
    return f"courses/lessons/{secrets.token_hex(16)}.{ext}"


class Category(models.Model):
    ICONS = [
        ("computer", "Computer"),
        ("description", "Document / Office"),
        ("web", "Web"),
        ("code", "Code"),
        ("campaign", "Marketing"),
        ("dns", "Networking / Server"),
        ("school", "General"),
    ]

    name = models.CharField(max_length=120)
    slug = models.SlugField(max_length=140, unique=True, blank=True)
    description = models.CharField(max_length=500, blank=True, default="")
    icon = models.CharField(max_length=40, choices=ICONS, default="school")
    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["sort_order", "name"]
        verbose_name_plural = "categories"

    def __str__(self) -> str:
        return self.name

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = _unique_slug(Category, self.name, self.pk)
        super().save(*args, **kwargs)


class Course(models.Model):
    class Difficulty(models.TextChoices):
        BEGINNER = "beginner", "Beginner"
        INTERMEDIATE = "intermediate", "Intermediate"
        ADVANCED = "advanced", "Advanced"

    category = models.ForeignKey(Category, null=True, blank=True, on_delete=models.SET_NULL, related_name="courses")
    title = models.CharField(max_length=200)
    slug = models.SlugField(max_length=220, unique=True, blank=True)
    subtitle = models.CharField(max_length=300, blank=True, default="")
    description = models.TextField(blank=True, default="")
    outcomes = models.TextField("what students will learn", blank=True, default="", help_text="One point per line.")
    requirements = models.TextField(blank=True, default="", help_text="One requirement per line.")
    difficulty = models.CharField(max_length=20, choices=Difficulty.choices, default=Difficulty.BEGINNER)
    language = models.CharField(max_length=40, default="English")
    duration_label = models.CharField("duration", max_length=60, blank=True, default="", help_text="e.g. 2–3 months")
    price = models.DecimalField(
        "price (₹)", max_digits=10, decimal_places=2, default=Decimal("0.00"),
        validators=[MinValueValidator(Decimal("0"))], help_text="0 = free course.",
    )
    mrp = models.DecimalField(
        "original price (₹)", max_digits=10, decimal_places=2, default=Decimal("0.00"),
        validators=[MinValueValidator(Decimal("0"))], help_text="Optional. Shown crossed out when higher than the price.",
    )
    thumbnail = models.ImageField(upload_to=thumbnail_path, blank=True)
    instructor_name = models.CharField(max_length=120, blank=True, default="Vinay Bhatt")
    instructor_bio = models.CharField(max_length=500, blank=True, default="")
    is_published = models.BooleanField("published", default=False, help_text="Only published courses appear in the app.")
    is_featured = models.BooleanField("featured on home screen", default=False)
    sort_order = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["sort_order", "-created_at"]

    def __str__(self) -> str:
        return self.title

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = _unique_slug(Course, self.title, self.pk)
        super().save(*args, **kwargs)

    @property
    def price_paise(self) -> int:
        return to_paise(self.price)

    @property
    def mrp_paise(self) -> int:
        return to_paise(self.mrp)

    @property
    def is_free(self) -> bool:
        return self.price_paise == 0


class Lesson(models.Model):
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name="lessons")
    section_title = models.CharField(
        "section", max_length=200, blank=True, default="", help_text="Optional module/chapter name used to group lessons."
    )
    title = models.CharField(max_length=200)
    content = models.TextField(help_text="Lesson text in Markdown. Use the preview to check how it looks.")
    reading_minutes = models.PositiveIntegerField(default=1, editable=False)
    is_free_preview = models.BooleanField("free preview", default=False, help_text="Anyone can read this lesson without enrolling.")
    is_published = models.BooleanField("published", default=True)
    sort_order = models.PositiveIntegerField("order", default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["sort_order", "id"]
        indexes = [models.Index(fields=["course", "sort_order"], name="lesson_course_order_idx")]

    def __str__(self) -> str:
        return self.title

    def save(self, *args, **kwargs):
        self.reading_minutes = reading_minutes(self.content)
        super().save(*args, **kwargs)


class LessonImage(models.Model):
    """Images uploaded for use inside a lesson's Markdown."""

    lesson = models.ForeignKey(Lesson, on_delete=models.CASCADE, related_name="images")
    image = models.ImageField(upload_to=lesson_image_path)
    alt_text = models.CharField("description", max_length=200, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return self.alt_text or self.image.name

    @property
    def markdown(self) -> str:
        if not self.image:
            return ""
        alt = (self.alt_text or "image").replace("[", "").replace("]", "")
        return f"![{alt}]({self.image.url})"


class Enrollment(models.Model):
    class Source(models.TextChoices):
        FREE = "free", "Free enrollment"
        PURCHASE = "purchase", "Purchased"
        ADMIN = "admin", "Added by admin"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="enrollments")
    course = models.ForeignKey(Course, on_delete=models.PROTECT, related_name="enrollments")
    source = models.CharField(max_length=20, choices=Source.choices, default=Source.ADMIN)
    payment = models.ForeignKey("payments.Payment", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-created_at"]
        constraints = [models.UniqueConstraint(fields=["user", "course"], name="uq_enrollment_user_course")]

    def __str__(self) -> str:
        return f"{self.user} → {self.course}"


class LessonProgress(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="lesson_progress")
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name="+")
    lesson = models.ForeignKey(Lesson, on_delete=models.CASCADE, related_name="progress")
    completed_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["user", "lesson"], name="uq_progress_user_lesson")]
        indexes = [models.Index(fields=["user", "course"], name="progress_user_course_idx")]
        verbose_name_plural = "lesson progress"


class Bookmark(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="bookmarks")
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name="bookmarks")
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-created_at"]
        constraints = [models.UniqueConstraint(fields=["user", "course"], name="uq_bookmark_user_course")]
