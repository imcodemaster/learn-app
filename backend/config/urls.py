from django.conf import settings
from django.contrib import admin
from django.urls import include, path, re_path
from django.views.static import serve

from core.views import throttled_admin_login

admin.site.site_header = "LearnInCreation Admin"
admin.site.site_title = "LearnInCreation Admin"
admin.site.index_title = "Courses, study center and students"

urlpatterns = [
    # Rate-limited login must come before the admin URLs so it takes priority.
    path(settings.ADMIN_URL + "login/", throttled_admin_login, name="admin_login_throttled"),
    path(settings.ADMIN_URL, admin.site.urls),
    path("api/", include("core.urls")),
    path("api/", include("accounts.urls")),
    path("api/", include("courses.urls")),
    path("api/", include("payments.urls")),
    path("api/", include("studycenter.urls")),
]

if settings.SERVE_MEDIA:
    urlpatterns += [
        re_path(r"^media/(?P<path>.*)$", serve, {"document_root": settings.MEDIA_ROOT, "show_indexes": False}),
    ]

handler404 = "core.views.not_found"
handler500 = "core.views.server_error"
