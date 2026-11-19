from django.urls import path

from . import views

urlpatterns = [
    path("auth/register", views.register, name="auth-register"),
    path("auth/login", views.login, name="auth-login"),
    path("auth/otp/send", views.otp_send, name="auth-otp-send"),
    path("auth/otp/verify", views.otp_verify, name="auth-otp-verify"),
    path("auth/google", views.google_login, name="auth-google"),
    path("auth/password/forgot", views.forgot_password, name="auth-password-forgot"),
    path("auth/password/reset", views.reset_password, name="auth-password-reset"),
    path("auth/logout", views.logout, name="auth-logout"),
    path("auth/logout-all", views.logout_all, name="auth-logout-all"),
    path("me", views.me, name="me"),
    path("me/password", views.change_password, name="me-password"),
    path("me/delete", views.delete_me, name="me-delete"),
]
