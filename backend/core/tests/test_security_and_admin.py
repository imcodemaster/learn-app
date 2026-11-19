from datetime import timedelta

from django.core.management import call_command
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone

from accounts.models import AuthToken, User
from core.utils import hash_token, new_token
from courses.models import Course, Lesson
from studycenter.models import Batch, Booking, Shift

from .helpers import STRONG_PASSWORD, ApiTestCase

INJECTION_PAYLOADS = [
    "' OR '1'='1",
    "1; DROP TABLE courses_course; --",
    "%' UNION SELECT password FROM accounts_user --",
    "\\'; SELECT pg_sleep(5); --",
    "_%",
]


class SecurityTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.course = self.make_course("Python for Beginners", price="499")

    def test_sql_injection_payloads_are_treated_as_plain_text(self):
        before = Course.objects.count()
        for payload in INJECTION_PAYLOADS:
            response = self.client.get("/api/courses", {"search": payload})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(self.data(response), [])
            self.assertEqual(self.client.get("/api/courses", {"category": payload}).status_code, 200)
            self.assertIn(self.client.get(f"/api/courses/{payload.replace('/', '')}").status_code, (404,))
            response = self.client.post("/api/auth/login", {"email": payload, "password": payload}, format="json")
            self.assertIn(response.status_code, (401, 422))
        self.assertEqual(Course.objects.count(), before)

    def test_tampered_and_expired_tokens(self):
        for header in ["Bearer li_" + "A" * 43, "Bearer ' OR 1=1 --", "Bearer", "Token abc"]:
            self.client.credentials(HTTP_AUTHORIZATION=header)
            self.assertEqual(self.client.get("/api/me").status_code, 401)
        user = self.make_user()
        token = new_token()
        AuthToken.objects.create(user=user, token_hash=hash_token(token), expires_at=timezone.now() - timedelta(seconds=1))
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        self.assertEqual(self.client.get("/api/me").status_code, 401)
        self.assertEqual(self.client.get("/api/courses").status_code, 200)  # public pages still work

    def test_mass_assignment_on_register(self):
        response = self.client.post("/api/auth/register", {
            "name": "Hacker", "email": "h@example.com", "password": STRONG_PASSWORD,
            "is_staff": True, "is_superuser": True, "role": "admin",
        }, format="json")
        self.assertEqual(response.status_code, 201)
        user = User.objects.get(email="h@example.com")
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)
        self.assertEqual(self.data(response)["user"]["role"], "student")

    def test_security_headers(self):
        response = self.client.get("/api/courses")
        self.assertEqual(response.headers["X-Content-Type-Options"], "nosniff")
        self.assertEqual(response.headers["X-Frame-Options"], "DENY")
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertIn("default-src 'none'", response.headers["Content-Security-Policy"])

    def test_unknown_api_route_returns_json(self):
        response = self.client.get("/api/does-not-exist")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["error"]["code"], "not_found")

    def test_invalid_json_body(self):
        response = self.client.generic("POST", "/api/auth/login", "{not json", content_type="application/json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "invalid_json")


class AdminPanelTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        call_command("seed_demo", verbosity=0)
        self.admin_user = User.objects.create_superuser(email="admin@example.com", password=STRONG_PASSWORD, name="Admin")

    def test_seed_is_idempotent(self):
        courses, lessons = Course.objects.count(), Lesson.objects.count()
        call_command("seed_demo", verbosity=0)
        self.assertEqual(Course.objects.count(), courses)
        self.assertEqual(Lesson.objects.count(), lessons)
        self.assertEqual(Batch.objects.count(), 12)
        self.assertEqual(Shift.objects.count(), 3)

    def test_admin_requires_staff(self):
        response = self.client.get(reverse("admin:index"))
        self.assertEqual(response.status_code, 302)
        student = self.make_user(email="student@example.com")
        self.client.force_login(student)
        self.assertEqual(self.client.get(reverse("admin:index")).status_code, 302)

    def test_admin_login_is_throttled(self):
        url = reverse("admin_login_throttled")
        for _ in range(10):
            self.client.post(url, {"username": "admin@example.com", "password": "wrong"})
        response = self.client.post(url, {"username": "admin@example.com", "password": STRONG_PASSWORD})
        self.assertEqual(response.status_code, 429)

    @override_settings(APP_ENV="local", PAYMENTS_MODE="mock")
    def test_admin_pages_render(self):
        student = self.make_user(email="student@example.com")
        self.login_as(student)
        batch = Batch.objects.first()
        self.client.post(f"/api/study-center/batches/{batch.pk}/book", {"seat_no": 1}, format="json")
        self.logout_client()
        self.client.force_login(self.admin_user)
        course = Course.objects.get(slug="python-for-beginners")
        lesson = course.lessons.first()
        booking = Booking.objects.first()
        urls = [
            reverse("admin:index"),
            reverse("admin:courses_course_changelist"),
            reverse("admin:courses_course_change", args=[course.pk]),
            reverse("admin:courses_course_add"),
            reverse("admin:courses_lesson_changelist"),
            reverse("admin:courses_lesson_change", args=[lesson.pk]),
            reverse("admin:courses_lesson_add") + f"?course={course.pk}",
            reverse("admin:courses_category_changelist"),
            reverse("admin:courses_enrollment_add"),
            reverse("admin:studycenter_batch_changelist"),
            reverse("admin:studycenter_batch_change", args=[batch.pk]),
            reverse("admin:studycenter_shift_change", args=[Shift.objects.first().pk]),
            reverse("admin:studycenter_booking_changelist"),
            reverse("admin:studycenter_booking_change", args=[booking.pk]),
            reverse("admin:payments_payment_changelist"),
            reverse("admin:accounts_user_changelist"),
            reverse("admin:accounts_user_change", args=[student.pk]),
            reverse("admin:accounts_user_add"),
            reverse("admin:core_faq_changelist"),
        ]
        for url in urls:
            response = self.client.get(url)
            self.assertEqual(response.status_code, 200, url)
        response = self.client.get(reverse("admin:core_sitesettings_changelist"))
        self.assertEqual(response.status_code, 302)  # jumps straight to the single settings page

    def test_admin_can_create_lesson(self):
        self.client.force_login(self.admin_user)
        course = Course.objects.get(slug="design-with-css3")
        response = self.client.post(reverse("admin:courses_lesson_add"), {
            "course": course.pk,
            "section_title": "Basics",
            "title": "Colours in CSS",
            "content": "## Colours\n\nUse `color: red;`",
            "sort_order": 1,
            "is_published": "on",
            "images-TOTAL_FORMS": "0",
            "images-INITIAL_FORMS": "0",
            "images-MIN_NUM_FORMS": "0",
            "images-MAX_NUM_FORMS": "1000",
        })
        self.assertEqual(response.status_code, 302, response.content[:2000])
        self.assertTrue(course.lessons.filter(title="Colours in CSS").exists())
