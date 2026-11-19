from django import forms
from django.contrib import admin, messages
from django.db.models import Count, Max
from django.urls import reverse
from django.utils.html import format_html

from core.admin_forms import sanitize_uploaded_image
from core.utils import format_rupees

from .models import Category, Course, Enrollment, Lesson, LessonImage


class MarkdownEditor(forms.Textarea):
    """Textarea with a formatting toolbar and live preview (see static/courses/admin)."""

    def __init__(self, attrs=None):
        base = {"rows": 26, "class": "li-markdown", "spellcheck": "true"}
        if attrs:
            base.update(attrs)
        super().__init__(base)

    class Media:
        css = {"all": ["courses/admin/lesson-editor.css"]}
        js = ["courses/admin/marked.umd.js", "courses/admin/lesson-editor.js"]


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ["name", "icon", "sort_order", "is_active", "course_total"]
    list_editable = ["sort_order", "is_active"]
    search_fields = ["name"]
    prepopulated_fields = {"slug": ["name"]}

    def get_queryset(self, request):
        return super().get_queryset(request).annotate(_courses=Count("courses"))

    @admin.display(description="Courses", ordering="_courses")
    def course_total(self, obj):
        return obj._courses


class CourseAdminForm(forms.ModelForm):
    class Meta:
        model = Course
        fields = "__all__"

    def clean_thumbnail(self):
        return sanitize_uploaded_image(self.cleaned_data.get("thumbnail"), max_side=1280)


class LessonInline(admin.TabularInline):
    model = Lesson
    fields = ["sort_order", "title", "section_title", "is_free_preview", "is_published", "reading_minutes"]
    readonly_fields = ["reading_minutes"]
    extra = 0
    show_change_link = True
    ordering = ["sort_order", "id"]
    verbose_name_plural = "Lessons (use “Add a lesson” above to write a new one)"

    def has_add_permission(self, request, obj=None):
        return False  # lessons are written in the full lesson editor


@admin.register(Course)
class CourseAdmin(admin.ModelAdmin):
    form = CourseAdminForm
    list_display = ["title", "category", "price_display", "is_published", "is_featured", "lessons_total", "students", "updated_at"]
    list_editable = ["is_published", "is_featured"]
    list_filter = ["is_published", "is_featured", "category", "difficulty"]
    search_fields = ["title", "subtitle", "description"]
    list_select_related = ["category"]
    prepopulated_fields = {"slug": ["title"]}
    readonly_fields = ["thumbnail_preview", "add_lesson_link", "created_at", "updated_at"]
    inlines = [LessonInline]
    actions = ["publish", "unpublish"]
    fieldsets = [
        (None, {"fields": ["title", "slug", "subtitle", "category", "add_lesson_link"]}),
        ("Pricing", {"fields": ["price", "mrp"]}),
        ("Details", {"fields": ["description", "outcomes", "requirements", "difficulty", "language", "duration_label"]}),
        ("Instructor", {"fields": ["instructor_name", "instructor_bio"]}),
        ("Image", {"fields": ["thumbnail", "thumbnail_preview"]}),
        ("Visibility", {"fields": ["is_published", "is_featured", "sort_order", "created_at", "updated_at"]}),
    ]

    def get_queryset(self, request):
        return super().get_queryset(request).annotate(
            _lessons=Count("lessons", distinct=True), _students=Count("enrollments", distinct=True)
        )

    @admin.display(description="Price", ordering="price")
    def price_display(self, obj):
        return "Free" if obj.is_free else format_rupees(obj.price_paise)

    @admin.display(description="Lessons", ordering="_lessons")
    def lessons_total(self, obj):
        return obj._lessons

    @admin.display(description="Students", ordering="_students")
    def students(self, obj):
        return obj._students

    @admin.display(description="Thumbnail")
    def thumbnail_preview(self, obj):
        if obj and obj.thumbnail:
            return format_html('<img src="{}" style="max-width:320px;border-radius:8px">', obj.thumbnail.url)
        return "No image yet"

    @admin.display(description="Lessons")
    def add_lesson_link(self, obj):
        if not obj or not obj.pk:
            return "Save the course first, then add lessons."
        url = reverse("admin:courses_lesson_add") + f"?course={obj.pk}"
        return format_html('<a class="button" href="{}">Add a lesson</a>', url)

    @admin.action(description="Publish selected courses")
    def publish(self, request, queryset):
        updated = queryset.update(is_published=True)
        self.message_user(request, f"Published {updated} course(s).", messages.SUCCESS)

    @admin.action(description="Unpublish selected courses (hide from the app)")
    def unpublish(self, request, queryset):
        updated = queryset.update(is_published=False)
        self.message_user(request, f"Unpublished {updated} course(s).", messages.SUCCESS)


class LessonAdminForm(forms.ModelForm):
    class Meta:
        model = Lesson
        fields = "__all__"
        widgets = {"content": MarkdownEditor()}


class LessonImageForm(forms.ModelForm):
    class Meta:
        model = LessonImage
        fields = ["image", "alt_text"]

    def clean_image(self):
        return sanitize_uploaded_image(self.cleaned_data.get("image"), max_side=1600)


class LessonImageInline(admin.TabularInline):
    model = LessonImage
    form = LessonImageForm
    extra = 1
    fields = ["image", "alt_text", "markdown_snippet"]
    readonly_fields = ["markdown_snippet"]
    verbose_name_plural = "Images for this lesson (upload, save, then paste the code into the text)"

    @admin.display(description="Code to paste into the lesson")
    def markdown_snippet(self, obj):
        if not obj or not obj.pk or not obj.image:
            return "Save the lesson to get the code."
        return format_html('<code style="user-select:all">{}</code>', obj.markdown)


@admin.register(Lesson)
class LessonAdmin(admin.ModelAdmin):
    form = LessonAdminForm
    list_display = ["title", "course", "section_title", "sort_order", "is_free_preview", "is_published", "reading_minutes", "updated_at"]
    list_editable = ["sort_order", "is_free_preview", "is_published"]
    list_filter = ["is_published", "is_free_preview", "course"]
    search_fields = ["title", "content", "course__title"]
    list_select_related = ["course"]
    autocomplete_fields = ["course"]
    inlines = [LessonImageInline]
    fieldsets = [
        (None, {"fields": ["course", "section_title", "title", "content"]}),
        ("Options", {"fields": ["sort_order", "is_free_preview", "is_published"]}),
    ]

    def get_changeform_initial_data(self, request):
        initial = super().get_changeform_initial_data(request)
        course_id = initial.get("course")
        if course_id and "sort_order" not in initial:
            try:
                highest = Lesson.objects.filter(course_id=int(course_id)).aggregate(m=Max("sort_order"))["m"]
                initial["sort_order"] = (highest or 0) + 1
            except (TypeError, ValueError):
                pass
        return initial


@admin.register(Enrollment)
class EnrollmentAdmin(admin.ModelAdmin):
    """Add an enrollment here to give a student access (e.g. after a cash payment)."""

    list_display = ["user", "course", "source", "created_at"]
    list_filter = ["source", "course"]
    search_fields = ["user__name", "user__email", "user__phone", "course__title"]
    autocomplete_fields = ["user", "course"]
    list_select_related = ["user", "course"]
    readonly_fields = ["payment"]
    fields = ["user", "course", "source", "payment", "created_at"]

    def get_changeform_initial_data(self, request):
        initial = super().get_changeform_initial_data(request)
        initial.setdefault("source", Enrollment.Source.ADMIN)
        return initial
