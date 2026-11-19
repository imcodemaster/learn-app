from django.urls import path

from . import views

urlpatterns = [
    path("health", views.health, name="health"),
    path("app/info", views.app_info, name="app-info"),
]
