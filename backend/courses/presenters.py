"""Turns course objects into the JSON shapes the app expects."""

from django.db.models import Count, Q

from core.api import absolute_url, base_url
from core.utils import absolutize_media_links, iso_utc, lines

from .models import Bookmark, Course, Enrollment, Lesson, LessonProgress


def published_lesson_count():
    return Count("lessons", filter=Q(lessons__is_published=True), distinct=True)


def course_queryset():
    return Course.objects.select_related("category").annotate(lesson_count=published_lesson_count())


def flags_for(user, course_ids: list[int]) -> tuple[set[int], set[int]]:
    """(enrolled course ids, bookmarked course ids) for a signed-in user."""
    if user is None or not user.is_authenticated or not course_ids:
        return set(), set()
    enrolled = set(Enrollment.objects.filter(user=user, course_id__in=course_ids).values_list("course_id", flat=True))
    saved = set(Bookmark.objects.filter(user=user, course_id__in=course_ids).values_list("course_id", flat=True))
    return enrolled, saved


def course_summary(request, course: Course, enrolled: bool = False, bookmarked: bool = False) -> dict:
    category = course.category
    return {
        "id": course.pk,
        "slug": course.slug,
        "title": course.title,
        "subtitle": course.subtitle,
        "thumbnail_url": absolute_url(request, course.thumbnail.url) if course.thumbnail else None,
        "category": {"id": category.pk, "name": category.name, "slug": category.slug, "icon": category.icon}
        if category else None,
        "difficulty": course.difficulty,
        "language": course.language,
        "duration_label": course.duration_label,
        "price_paise": course.price_paise,
        "mrp_paise": course.mrp_paise,
        "is_free": course.is_free,
        "lesson_count": int(getattr(course, "lesson_count", 0) or 0),
        "instructor_name": course.instructor_name,
        "is_featured": course.is_featured,
        "is_enrolled": enrolled,
        "is_bookmarked": bookmarked,
    }


def course_list(request, courses: list[Course]) -> list[dict]:
    enrolled, saved = flags_for(request.user, [c.pk for c in courses])
    return [course_summary(request, c, c.pk in enrolled, c.pk in saved) for c in courses]


def progress_for(user, course: Course, total: int) -> dict:
    completed = LessonProgress.objects.filter(
        user=user, course=course, lesson__is_published=True
    ).count()
    percent = round(completed * 100 / total) if total else 0
    return {"completed": completed, "total": total, "percent": min(100, percent)}


def course_detail(request, course: Course) -> dict:
    user = request.user if request.user.is_authenticated else None
    enrolled_ids, saved_ids = flags_for(user, [course.pk])
    enrolled = course.pk in enrolled_ids
    lessons = list(Lesson.objects.filter(course=course, is_published=True).order_by("sort_order", "id"))
    completed_ids = set()
    if user is not None:
        completed_ids = set(
            LessonProgress.objects.filter(user=user, course=course).values_list("lesson_id", flat=True)
        )
    data = course_summary(request, course, enrolled, course.pk in saved_ids)
    data["lesson_count"] = len(lessons)
    data.update({
        "description": course.description,
        "outcomes": lines(course.outcomes),
        "requirements": lines(course.requirements),
        "instructor_bio": course.instructor_bio,
        "lessons": [
            {
                "id": lesson.pk,
                "title": lesson.title,
                "section_title": lesson.section_title,
                "reading_minutes": lesson.reading_minutes,
                "is_free_preview": lesson.is_free_preview,
                "is_completed": lesson.pk in completed_ids,
                "is_locked": not (enrolled or lesson.is_free_preview),
            }
            for lesson in lessons
        ],
        "progress": progress_for(user, course, len(lessons)) if enrolled and user is not None else None,
        "updated_at": iso_utc(course.updated_at),
    })
    return data


def lesson_detail(request, lesson: Lesson, completed: bool, prev_id, next_id) -> dict:
    return {
        "id": lesson.pk,
        "course_id": lesson.course_id,
        "title": lesson.title,
        "section_title": lesson.section_title,
        "content_md": absolutize_media_links(lesson.content, base_url(request)),
        "reading_minutes": lesson.reading_minutes,
        "is_free_preview": lesson.is_free_preview,
        "is_completed": completed,
        "prev_lesson_id": prev_id,
        "next_lesson_id": next_id,
        "updated_at": iso_utc(lesson.updated_at),
    }


def categories_with_counts():
    from .models import Category

    return (
        Category.objects.filter(is_active=True)
        .annotate(course_count=Count("courses", filter=Q(courses__is_published=True), distinct=True))
        .order_by("sort_order", "name")
    )
