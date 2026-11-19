import re

from django.db.models import Count, Q
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated

from core.api import ApiError, not_found, ok, paginate
from core.utils import iso_utc

from .models import Bookmark, Course, Enrollment, Lesson, LessonProgress
from .presenters import (
    categories_with_counts,
    course_detail,
    course_list,
    course_queryset,
    course_summary,
    lesson_detail,
    progress_for,
)

_ID = re.compile(r"^[0-9]{1,18}$")
_SLUG = re.compile(r"^[A-Za-z0-9\-]{1,220}$")

SORTS = {
    "recommended": ["-is_featured", "sort_order", "-id"],
    "newest": ["-created_at", "-id"],
    "popular": ["-enroll_count", "-id"],
    "price_low": ["price", "-id"],
    "price_high": ["-price", "-id"],
}


def _current_user(request):
    return request.user if request.user.is_authenticated else None


def _get_course(ref: str, user) -> Course:
    queryset = course_queryset()
    if _ID.match(ref):
        course = queryset.filter(pk=int(ref)).first()
    elif _SLUG.match(ref):
        course = queryset.filter(slug=ref).first()
    else:
        course = None
    if course is None:
        raise not_found("Course not found.")
    if not course.is_published:
        # Students who already enrolled keep access if a course is unpublished later.
        if user is None or not Enrollment.objects.filter(user=user, course=course).exists():
            raise not_found("Course not found.")
    return course


@api_view(["GET"])
def categories(request):
    return ok([
        {
            "id": c.pk,
            "name": c.name,
            "slug": c.slug,
            "description": c.description,
            "icon": c.icon,
            "course_count": c.course_count,
        }
        for c in categories_with_counts()
    ])


@api_view(["GET"])
def courses(request):
    params = request.query_params
    queryset = course_queryset().filter(is_published=True)

    search = (params.get("search") or "").strip()[:100]
    if search:
        queryset = queryset.filter(
            Q(title__icontains=search) | Q(subtitle__icontains=search) | Q(description__icontains=search)
        )
    category = (params.get("category") or "").strip()
    if category:
        if _ID.match(category):
            queryset = queryset.filter(category_id=int(category))
        elif _SLUG.match(category):
            queryset = queryset.filter(category__slug=category)
        else:
            queryset = queryset.none()
    if params.get("featured") in ("1", "true"):
        queryset = queryset.filter(is_featured=True)
    price = params.get("price")
    if price == "free":
        queryset = queryset.filter(price=0)
    elif price == "paid":
        queryset = queryset.filter(price__gt=0)

    sort = params.get("sort") or "recommended"
    if sort not in SORTS:
        sort = "recommended"
    if sort == "popular":
        queryset = queryset.annotate(enroll_count=Count("enrollments", distinct=True))
    queryset = queryset.order_by(*SORTS[sort])

    items, meta = paginate(request, queryset)
    return ok(course_list(request, items), meta=meta)


@api_view(["GET"])
def course(request, ref):
    return ok(course_detail(request, _get_course(ref, _current_user(request))))


@api_view(["GET"])
def lesson(request, ref, lesson_id):
    user = _current_user(request)
    course_obj = _get_course(ref, user)
    lesson_obj = Lesson.objects.filter(pk=lesson_id, course=course_obj, is_published=True).first()
    if lesson_obj is None:
        raise not_found("Lesson not found.")
    enrolled = user is not None and Enrollment.objects.filter(user=user, course=course_obj).exists()
    if not lesson_obj.is_free_preview and not enrolled:
        if user is None:
            raise ApiError(401, "unauthenticated", "Sign in and enroll to read this lesson.")
        raise ApiError(403, "not_enrolled", "Enroll in this course to read this lesson.")

    ordered_ids = list(
        Lesson.objects.filter(course=course_obj, is_published=True).order_by("sort_order", "id").values_list("id", flat=True)
    )
    index = ordered_ids.index(lesson_obj.pk)
    prev_id = ordered_ids[index - 1] if index > 0 else None
    next_id = ordered_ids[index + 1] if index + 1 < len(ordered_ids) else None
    completed = user is not None and LessonProgress.objects.filter(user=user, lesson=lesson_obj).exists()
    return ok(lesson_detail(request, lesson_obj, completed, prev_id, next_id))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def enroll(request, course_id):
    course_obj = course_queryset().filter(pk=course_id, is_published=True).first()
    if course_obj is None:
        raise not_found("Course not found.")
    if Enrollment.objects.filter(user=request.user, course=course_obj).exists():
        return ok({"enrolled": True, "course_id": course_obj.pk})
    if not course_obj.is_free:
        raise ApiError(402, "payment_required", "This is a paid course. Buy it to enroll.")
    Enrollment.objects.get_or_create(user=request.user, course=course_obj, defaults={"source": Enrollment.Source.FREE})
    return ok({"enrolled": True, "course_id": course_obj.pk}, 201)


@api_view(["POST", "DELETE"])
@permission_classes([IsAuthenticated])
def bookmark(request, course_id):
    if request.method == "DELETE":
        Bookmark.objects.filter(user=request.user, course_id=course_id).delete()
        return ok({"bookmarked": False, "course_id": course_id})
    course_obj = Course.objects.filter(pk=course_id, is_published=True).first()
    if course_obj is None:
        raise not_found("Course not found.")
    Bookmark.objects.get_or_create(user=request.user, course=course_obj)
    return ok({"bookmarked": True, "course_id": course_obj.pk})


@api_view(["POST", "DELETE"])
@permission_classes([IsAuthenticated])
def complete_lesson(request, lesson_id):
    lesson_obj = Lesson.objects.select_related("course").filter(pk=lesson_id, is_published=True).first()
    if lesson_obj is None:
        raise not_found("Lesson not found.")
    if not Enrollment.objects.filter(user=request.user, course_id=lesson_obj.course_id).exists():
        raise ApiError(403, "not_enrolled", "Enroll in this course to track your progress.")
    if request.method == "POST":
        LessonProgress.objects.get_or_create(user=request.user, lesson=lesson_obj, defaults={"course_id": lesson_obj.course_id})
    else:
        LessonProgress.objects.filter(user=request.user, lesson=lesson_obj).delete()
    total = Lesson.objects.filter(course_id=lesson_obj.course_id, is_published=True).count()
    return ok({
        "lesson_id": lesson_obj.pk,
        "is_completed": request.method == "POST",
        "progress": progress_for(request.user, lesson_obj.course, total),
    })


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_enrollments(request):
    user = request.user
    enrollments = list(
        Enrollment.objects.filter(user=user).select_related("course", "course__category").order_by("-created_at")
    )
    course_ids = [e.course_id for e in enrollments]
    lesson_ids_by_course: dict[int, list[int]] = {}
    for row in (
        Lesson.objects.filter(course_id__in=course_ids, is_published=True)
        .order_by("sort_order", "id")
        .values("id", "course_id")
    ):
        lesson_ids_by_course.setdefault(row["course_id"], []).append(row["id"])
    completed = set(
        LessonProgress.objects.filter(user=user, course_id__in=course_ids).values_list("lesson_id", flat=True)
    )
    saved = set(Bookmark.objects.filter(user=user, course_id__in=course_ids).values_list("course_id", flat=True))

    items = []
    for enrollment in enrollments:
        course_obj = enrollment.course
        lesson_ids = lesson_ids_by_course.get(course_obj.pk, [])
        course_obj.lesson_count = len(lesson_ids)
        done = sum(1 for lid in lesson_ids if lid in completed)
        total = len(lesson_ids)
        items.append({
            "course": course_summary(request, course_obj, True, course_obj.pk in saved),
            "enrolled_at": iso_utc(enrollment.created_at),
            "progress": {
                "completed": done,
                "total": total,
                "percent": round(done * 100 / total) if total else 0,
            },
            "next_lesson_id": next((lid for lid in lesson_ids if lid not in completed), None),
        })
    return ok(items)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_bookmarks(request):
    ordered_ids = list(
        Bookmark.objects.filter(user=request.user, course__is_published=True)
        .order_by("-created_at")
        .values_list("course_id", flat=True)
    )
    by_id = {c.pk: c for c in course_queryset().filter(pk__in=ordered_ids)}
    return ok(course_list(request, [by_id[i] for i in ordered_ids if i in by_id]))
