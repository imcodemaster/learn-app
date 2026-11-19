from django.urls import path

from . import views

urlpatterns = [
    path("study-center", views.info, name="study-center"),
    path("study-center/batches", views.batches, name="study-center-batches"),
    path("study-center/batches/<int:batch_id>", views.batch_detail, name="study-center-batch"),
    path("study-center/batches/<int:batch_id>/book", views.book_batch, name="study-center-book-batch"),
    path("study-center/library/availability", views.library_availability, name="study-center-library"),
    path("study-center/library/book", views.book_library, name="study-center-book-library"),
    path("me/bookings", views.my_bookings, name="my-bookings"),
    path("me/bookings/<int:booking_id>", views.my_booking, name="my-booking"),
    path("me/bookings/<int:booking_id>/cancel", views.cancel_my_booking, name="my-booking-cancel"),
]
