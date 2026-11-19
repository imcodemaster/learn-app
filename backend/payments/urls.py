from django.urls import path

from . import views

urlpatterns = [
    path("payments/course-order", views.course_order, name="payment-course-order"),
    path("payments/booking-order", views.booking_order, name="payment-booking-order"),
    path("payments/verify", views.verify, name="payment-verify"),
    path("payments/mock-complete", views.mock_complete, name="payment-mock-complete"),
    path("payments/webhook", views.razorpay_webhook, name="payment-webhook"),
    path("me/payments", views.my_payments, name="my-payments"),
]
