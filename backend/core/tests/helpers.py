from datetime import timedelta
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import AuthToken, User
from core.utils import hash_token, new_token
from courses.models import Category, Course, Lesson

STRONG_PASSWORD = "Learn2026xyz"


# Links in API responses are built from the test request ("http://testserver"),
# whatever PUBLIC_BASE_URL the local .env sets for phones on the Wi-Fi.
@override_settings(PUBLIC_BASE_URL="")
class ApiTestCase(TestCase):
    def setUp(self):
        cache.clear()  # reset rate-limit counters between tests
        self.client = APIClient()

    # ---------------------------------------------------------------- helpers
    def make_user(self, email="asha@example.com", password=STRONG_PASSWORD, **extra) -> User:
        extra.setdefault("name", "Asha")
        return User.objects.create_user(email=email, password=password, **extra)

    def token_for(self, user: User, days: int = 1) -> str:
        token = new_token()
        AuthToken.objects.create(user=user, token_hash=hash_token(token), expires_at=timezone.now() + timedelta(days=days))
        return token

    def login_as(self, user: User) -> str:
        token = self.token_for(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        return token

    def logout_client(self):
        self.client.credentials()

    def make_course(self, title="Python for Beginners", price="0", published=True, lessons=2, free_preview_first=True,
                    category=None) -> Course:
        if category is None:
            category, _ = Category.objects.get_or_create(slug="programming", defaults={"name": "Programming"})
        course = Course.objects.create(
            title=title, category=category, price=Decimal(price), is_published=published, subtitle=f"{title} subtitle"
        )
        for index in range(lessons):
            Lesson.objects.create(
                course=course,
                title=f"Lesson {index + 1}",
                content=f"# Lesson {index + 1}\n\nSome text with an image ![x](/media/courses/lessons/x.png)",
                sort_order=index + 1,
                is_free_preview=free_preview_first and index == 0,
            )
        return course

    @staticmethod
    def data(response):
        return response.json()["data"]

    @staticmethod
    def error(response):
        return response.json()["error"]
