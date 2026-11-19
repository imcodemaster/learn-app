from datetime import date, time
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from core import seed_content as content
from core.models import Faq, SiteSettings
from courses.models import Category, Course, Lesson
from studycenter.models import Batch, Shift


def _time(hhmm: str) -> time:
    hours, minutes = hhmm.split(":")
    return time(int(hours), int(minutes))


def _first_of_next_month(today: date) -> date:
    return date(today.year + (today.month // 12), today.month % 12 + 1, 1)


class Command(BaseCommand):
    help = "Adds the LearnInCreation sample catalog, lessons, study-center batches, library shifts and FAQs."

    @transaction.atomic
    def handle(self, *args, **options):
        site = SiteSettings.load()
        if not site.about:
            site.about = content.ABOUT
            site.save()

        if not Faq.objects.exists():
            for order, (question, answer) in enumerate(content.FAQS, start=1):
                Faq.objects.create(question=question, answer=answer, sort_order=order)

        categories = {}
        for order, (slug, name, icon, description) in enumerate(content.CATEGORIES, start=1):
            category, _ = Category.objects.get_or_create(
                slug=slug, defaults={"name": name, "icon": icon, "description": description, "sort_order": order}
            )
            categories[slug] = category

        new_courses = 0
        courses = {}
        for order, (slug, title, cat, subtitle, price, mrp, duration, featured, outcomes) in enumerate(content.COURSES, start=1):
            course, created = Course.objects.get_or_create(
                slug=slug,
                defaults={
                    "title": title,
                    "category": categories[cat],
                    "subtitle": subtitle,
                    "description": subtitle + "\n\nTaught step by step by LearnInCreation, with short lessons and practice tasks.",
                    "outcomes": "\n".join(outcomes),
                    "requirements": "A computer or smartphone with internet\nNo prior experience needed",
                    "price": Decimal(price),
                    "mrp": Decimal(mrp),
                    "duration_label": duration,
                    "is_featured": featured,
                    "is_published": True,
                    "sort_order": order,
                    "instructor_name": "Vinay Bhatt",
                    "instructor_bio": "Founder of LearnInCreation. B.Sc. (Kumaun University); certified in full-stack "
                                      "web development, digital marketing and ethical hacking.",
                },
            )
            new_courses += int(created)
            courses[slug] = course

        new_lessons = 0
        for slug, lessons in content.LESSONS.items():
            course = courses[slug]
            if course.lessons.exists():
                continue
            for order, (section, title, free_preview, body) in enumerate(lessons, start=1):
                Lesson.objects.create(
                    course=course, section_title=section, title=title, content=body.strip(),
                    is_free_preview=free_preview, sort_order=order,
                )
                new_lessons += 1

        new_batches = 0
        start = _first_of_next_month(timezone.localdate())
        for index, (title, course_slug, fee) in enumerate(content.BATCHES):
            if Batch.objects.filter(title=title).exists():
                continue
            begins, ends = content.BATCH_SLOTS[index % len(content.BATCH_SLOTS)]
            Batch.objects.create(
                title=title,
                course=courses.get(course_slug),
                description="Classroom batch at the LearnInCreation Study Center with hands-on practice.",
                days_label="Mon–Sat",
                start_time=_time(begins),
                end_time=_time(ends),
                start_date=start,
                duration_label="2–3 months",
                total_seats=10,
                seats_per_row=5,
                fee=Decimal(fee),
                booking_amount=Decimal(fee),
            )
            new_batches += 1

        new_shifts = 0
        for order, (name, begins, ends, fee) in enumerate(content.SHIFTS, start=1):
            _, created = Shift.objects.get_or_create(
                name=name,
                defaults={"start_time": _time(begins), "end_time": _time(ends), "monthly_fee": Decimal(fee), "sort_order": order},
            )
            new_shifts += int(created)

        self.stdout.write(self.style.SUCCESS(
            f"Sample data ready: {new_courses} new courses, {new_lessons} new lessons, "
            f"{new_batches} new batches, {new_shifts} new library shifts."
        ))
