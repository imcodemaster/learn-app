from django.urls import path

from . import views

urlpatterns = [
    path("categories", views.categories, name="categories"),
    path("courses", views.courses, name="courses"),
    path("courses/<int:course_id>/enroll", views.enroll, name="course-enroll"),
    path("courses/<int:course_id>/bookmark", views.bookmark, name="course-bookmark"),
    path("courses/<str:ref>/lessons/<int:lesson_id>", views.lesson, name="course-lesson"),
    path("courses/<str:ref>", views.course, name="course-detail"),
    path("lessons/<int:lesson_id>/complete", views.complete_lesson, name="lesson-complete"),
    path("me/enrollments", views.my_enrollments, name="my-enrollments"),
    path("me/bookmarks", views.my_bookmarks, name="my-bookmarks"),
]
