from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models


class SiteSettings(models.Model):
    """Single row of organisation details shown in the app (edit in the admin)."""

    org_name = models.CharField("organisation name", max_length=120, default="LearnInCreation")
    tagline = models.CharField(max_length=200, default="Learn Create & Innovate")
    hero_title = models.CharField("home screen headline", max_length=200, default="Learn Coding, Build Your Future")
    about = models.TextField("about text", blank=True, default="")
    phone = models.CharField(max_length=40, default="+91 6395677914")
    email = models.EmailField(default="thevinaybhatt@gmail.com")
    address = models.CharField(max_length=255, default="Rudrapur, Uttarakhand, India")
    hours = models.CharField("opening hours", max_length=120, default="Mon–Sat, 10:00 AM – 6:00 PM")
    website = models.URLField(default="https://learnincreation.com")
    youtube_url = models.URLField(blank=True, default="https://www.youtube.com/@LearnincreationIndia")
    instagram_url = models.URLField(blank=True, default="https://www.instagram.com/learnincreation/")
    linkedin_url = models.URLField(blank=True, default="https://www.linkedin.com/company/13744828/")
    privacy_url = models.URLField("privacy policy link", blank=True, default="https://learnincreation.com/privacy.html")
    terms_url = models.URLField("terms link", blank=True, default="https://learnincreation.com/terms.html")

    center_name = models.CharField("study center name", max_length=120, default="LearnInCreation Study Center")
    center_address = models.CharField("study center address", max_length=255, default="Rudrapur, Uttarakhand, India")
    center_hours = models.CharField("study center hours", max_length=120, default="Mon–Sat, 10:00 AM – 6:00 PM")

    library_enabled = models.BooleanField("library desk booking open", default=True)
    library_total_desks = models.PositiveIntegerField(
        "number of library desks", default=24, validators=[MinValueValidator(1), MaxValueValidator(500)]
    )
    library_desks_per_row = models.PositiveIntegerField(
        "desks per row (seat map)", default=6, validators=[MinValueValidator(1), MaxValueValidator(20)]
    )
    library_max_months = models.PositiveIntegerField(
        "longest booking (months)", default=6, validators=[MinValueValidator(1), MaxValueValidator(12)]
    )
    library_advance_days = models.PositiveIntegerField(
        "how far ahead students can book (days)", default=30, validators=[MaxValueValidator(365)]
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Site settings"
        verbose_name_plural = "Site settings"

    def __str__(self) -> str:
        return "Site settings"

    def save(self, *args, **kwargs):
        self.pk = 1  # always a single row
        super().save(*args, **kwargs)

    @classmethod
    def load(cls) -> "SiteSettings":
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj


class Faq(models.Model):
    question = models.CharField(max_length=300)
    answer = models.TextField()
    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["sort_order", "id"]
        verbose_name = "FAQ"
        verbose_name_plural = "FAQs"

    def __str__(self) -> str:
        return self.question
