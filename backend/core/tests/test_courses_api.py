from courses.models import Bookmark, Category, Enrollment

from .helpers import ApiTestCase


class CourseApiTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.free = self.make_course("Basics of Computer Fundamentals", price="0", lessons=2)
        self.paid = self.make_course("Python for Beginners", price="499", lessons=3)
        self.hidden = self.make_course("Secret Draft", price="0", published=False)
        self.user = self.make_user()

    def test_catalog_lists_only_published_courses(self):
        response = self.client.get("/api/courses")
        self.assertEqual(response.status_code, 200)
        titles = [c["title"] for c in self.data(response)]
        self.assertIn("Python for Beginners", titles)
        self.assertNotIn("Secret Draft", titles)
        meta = response.json()["meta"]
        self.assertEqual(meta["total"], 2)
        paid = next(c for c in self.data(response) if c["id"] == self.paid.pk)
        self.assertEqual(paid["price_paise"], 49900)
        self.assertEqual(paid["lesson_count"], 3)
        self.assertFalse(paid["is_free"])

    def test_search_filters_and_sorting(self):
        self.assertEqual(len(self.data(self.client.get("/api/courses?search=python"))), 1)
        self.assertEqual(len(self.data(self.client.get("/api/courses?price=free"))), 1)
        self.assertEqual(len(self.data(self.client.get("/api/courses?category=programming"))), 2)
        self.assertEqual(len(self.data(self.client.get("/api/courses?category=unknown-category"))), 0)
        prices = [c["price_paise"] for c in self.data(self.client.get("/api/courses?sort=price_high"))]
        self.assertEqual(prices, sorted(prices, reverse=True))
        self.assertEqual(self.client.get("/api/courses?sort=popular&page=1&per_page=1").json()["meta"]["total_pages"], 2)

    def test_categories(self):
        Category.objects.create(name="Empty", slug="empty")
        data = self.data(self.client.get("/api/categories"))
        programming = next(c for c in data if c["slug"] == "programming")
        self.assertEqual(programming["course_count"], 2)

    def test_unpublished_course_is_hidden(self):
        self.assertEqual(self.client.get(f"/api/courses/{self.hidden.slug}").status_code, 404)
        self.assertEqual(self.client.get(f"/api/courses/{self.hidden.pk}").status_code, 404)

    def test_lesson_locks_for_guests(self):
        detail = self.data(self.client.get(f"/api/courses/{self.paid.slug}"))
        self.assertEqual([lesson["is_locked"] for lesson in detail["lessons"]], [False, True, True])
        self.assertIsNone(detail["progress"])

    def test_lesson_access_rules(self):
        first, second = list(self.paid.lessons.order_by("sort_order"))[:2]
        url = f"/api/courses/{self.paid.pk}/lessons/"
        response = self.client.get(url + str(first.pk))  # free preview, no login
        self.assertEqual(response.status_code, 200)
        self.assertIn("http://testserver/media/courses/lessons/x.png", self.data(response)["content_md"])
        self.assertEqual(self.client.get(url + str(second.pk)).status_code, 401)
        self.login_as(self.user)
        response = self.client.get(url + str(second.pk))
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.error(response)["code"], "not_enrolled")
        Enrollment.objects.create(user=self.user, course=self.paid, source="admin")
        response = self.client.get(url + str(second.pk))
        self.assertEqual(response.status_code, 200)
        body = self.data(response)
        self.assertEqual(body["prev_lesson_id"], first.pk)
        # A lesson id from another course is not reachable through this course.
        other = self.free.lessons.first()
        self.assertEqual(self.client.get(url + str(other.pk)).status_code, 404)

    def test_free_enrollment_and_progress(self):
        self.login_as(self.user)
        response = self.client.post(f"/api/courses/{self.free.pk}/enroll")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.client.post(f"/api/courses/{self.free.pk}/enroll").status_code, 200)  # idempotent
        items = self.data(self.client.get("/api/me/enrollments"))
        self.assertEqual(items[0]["progress"], {"completed": 0, "total": 2, "percent": 0})

        lesson = self.free.lessons.order_by("sort_order").first()
        response = self.client.post(f"/api/lessons/{lesson.pk}/complete")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.data(response)["progress"]["percent"], 50)
        items = self.data(self.client.get("/api/me/enrollments"))
        self.assertEqual(items[0]["progress"]["completed"], 1)
        self.assertNotEqual(items[0]["next_lesson_id"], lesson.pk)
        self.assertEqual(self.client.delete(f"/api/lessons/{lesson.pk}/complete").status_code, 200)

    def test_paid_course_needs_payment(self):
        self.login_as(self.user)
        response = self.client.post(f"/api/courses/{self.paid.pk}/enroll")
        self.assertEqual(response.status_code, 402)
        lesson = self.paid.lessons.first()
        self.assertEqual(self.client.post(f"/api/lessons/{lesson.pk}/complete").status_code, 403)

    def test_bookmarks(self):
        self.assertEqual(self.client.post(f"/api/courses/{self.paid.pk}/bookmark").status_code, 401)
        self.login_as(self.user)
        self.assertEqual(self.client.post(f"/api/courses/{self.paid.pk}/bookmark").status_code, 200)
        self.assertEqual(self.client.post(f"/api/courses/{self.paid.pk}/bookmark").status_code, 200)  # idempotent
        self.assertEqual(Bookmark.objects.filter(user=self.user).count(), 1)
        saved = self.data(self.client.get("/api/me/bookmarks"))
        self.assertEqual([c["id"] for c in saved], [self.paid.pk])
        self.assertTrue(saved[0]["is_bookmarked"])
        listing = self.data(self.client.get("/api/courses"))
        self.assertTrue(next(c for c in listing if c["id"] == self.paid.pk)["is_bookmarked"])
        self.assertEqual(self.client.delete(f"/api/courses/{self.paid.pk}/bookmark").status_code, 200)
        self.assertEqual(self.data(self.client.get("/api/me/bookmarks")), [])
        self.assertEqual(self.client.post(f"/api/courses/{self.hidden.pk}/bookmark").status_code, 404)
