import 'json.dart';

class CategoryRef {
  const CategoryRef({required this.id, required this.name, required this.slug, required this.icon});

  final int id;
  final String name;
  final String slug;
  final String icon;

  factory CategoryRef.fromJson(Map<String, dynamic> json) => CategoryRef(
        id: jInt(json['id']),
        name: jStr(json['name']),
        slug: jStr(json['slug']),
        icon: jStr(json['icon'], 'school'),
      );
}

class CourseCategory {
  const CourseCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.icon,
    required this.courseCount,
  });

  final int id;
  final String name;
  final String slug;
  final String description;
  final String icon;
  final int courseCount;

  factory CourseCategory.fromJson(Map<String, dynamic> json) => CourseCategory(
        id: jInt(json['id']),
        name: jStr(json['name']),
        slug: jStr(json['slug']),
        description: jStr(json['description']),
        icon: jStr(json['icon'], 'school'),
        courseCount: jInt(json['course_count']),
      );
}

class CourseSummary {
  CourseSummary({
    required this.id,
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
    required this.category,
    required this.difficulty,
    required this.language,
    required this.durationLabel,
    required this.pricePaise,
    required this.mrpPaise,
    required this.isFree,
    required this.lessonCount,
    required this.instructorName,
    required this.isFeatured,
    required this.isEnrolled,
    required this.isBookmarked,
  });

  final int id;
  final String slug;
  final String title;
  final String subtitle;
  final String? thumbnailUrl;
  final CategoryRef? category;
  final String difficulty;
  final String language;
  final String durationLabel;
  final int pricePaise;
  final int mrpPaise;
  final bool isFree;
  final int lessonCount;
  final String instructorName;
  final bool isFeatured;
  bool isEnrolled;
  bool isBookmarked;

  factory CourseSummary.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    return CourseSummary(
      id: jInt(json['id']),
      slug: jStr(json['slug']),
      title: jStr(json['title']),
      subtitle: jStr(json['subtitle']),
      thumbnailUrl: jStrOrNull(json['thumbnail_url']),
      category: category is Map ? CategoryRef.fromJson(jMap(category)) : null,
      difficulty: jStr(json['difficulty'], 'beginner'),
      language: jStr(json['language'], 'English'),
      durationLabel: jStr(json['duration_label']),
      pricePaise: jInt(json['price_paise']),
      mrpPaise: jInt(json['mrp_paise']),
      isFree: jBool(json['is_free']),
      lessonCount: jInt(json['lesson_count']),
      instructorName: jStr(json['instructor_name']),
      isFeatured: jBool(json['is_featured']),
      isEnrolled: jBool(json['is_enrolled']),
      isBookmarked: jBool(json['is_bookmarked']),
    );
  }

  bool get comingSoon => lessonCount == 0;
}

class Progress {
  const Progress({required this.completed, required this.total, required this.percent});

  final int completed;
  final int total;
  final int percent;

  static const empty = Progress(completed: 0, total: 0, percent: 0);

  factory Progress.fromJson(Map<String, dynamic> json) => Progress(
        completed: jInt(json['completed']),
        total: jInt(json['total']),
        percent: jInt(json['percent']),
      );

  double get fraction => total == 0 ? 0 : (completed / total).clamp(0, 1).toDouble();
}

class LessonSummary {
  LessonSummary({
    required this.id,
    required this.title,
    required this.sectionTitle,
    required this.readingMinutes,
    required this.isFreePreview,
    required this.isCompleted,
    required this.isLocked,
  });

  final int id;
  final String title;
  final String sectionTitle;
  final int readingMinutes;
  final bool isFreePreview;
  bool isCompleted;
  final bool isLocked;

  factory LessonSummary.fromJson(Map<String, dynamic> json) => LessonSummary(
        id: jInt(json['id']),
        title: jStr(json['title']),
        sectionTitle: jStr(json['section_title']),
        readingMinutes: jInt(json['reading_minutes'], 1),
        isFreePreview: jBool(json['is_free_preview']),
        isCompleted: jBool(json['is_completed']),
        isLocked: jBool(json['is_locked']),
      );
}

class CourseDetail {
  CourseDetail({
    required this.summary,
    required this.description,
    required this.outcomes,
    required this.requirements,
    required this.instructorBio,
    required this.lessons,
    required this.progress,
  });

  final CourseSummary summary;
  final String description;
  final List<String> outcomes;
  final List<String> requirements;
  final String instructorBio;
  final List<LessonSummary> lessons;
  final Progress? progress;

  factory CourseDetail.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'];
    return CourseDetail(
      summary: CourseSummary.fromJson(json),
      description: jStr(json['description']),
      outcomes: jStrings(json['outcomes']),
      requirements: jStrings(json['requirements']),
      instructorBio: jStr(json['instructor_bio']),
      lessons: jList(json['lessons']).map(LessonSummary.fromJson).toList(),
      progress: progress is Map ? Progress.fromJson(jMap(progress)) : null,
    );
  }

  /// First lesson not yet completed (or the first lesson).
  LessonSummary? get nextLesson {
    for (final lesson in lessons) {
      if (!lesson.isCompleted && !lesson.isLocked) return lesson;
    }
    return lessons.isEmpty ? null : lessons.first;
  }
}

class LessonDetail {
  LessonDetail({
    required this.id,
    required this.courseId,
    required this.title,
    required this.sectionTitle,
    required this.contentMd,
    required this.readingMinutes,
    required this.isFreePreview,
    required this.isCompleted,
    required this.prevLessonId,
    required this.nextLessonId,
  });

  final int id;
  final int courseId;
  final String title;
  final String sectionTitle;
  final String contentMd;
  final int readingMinutes;
  final bool isFreePreview;
  bool isCompleted;
  final int? prevLessonId;
  final int? nextLessonId;

  factory LessonDetail.fromJson(Map<String, dynamic> json) => LessonDetail(
        id: jInt(json['id']),
        courseId: jInt(json['course_id']),
        title: jStr(json['title']),
        sectionTitle: jStr(json['section_title']),
        contentMd: jStr(json['content_md']),
        readingMinutes: jInt(json['reading_minutes'], 1),
        isFreePreview: jBool(json['is_free_preview']),
        isCompleted: jBool(json['is_completed']),
        prevLessonId: jIntOrNull(json['prev_lesson_id']),
        nextLessonId: jIntOrNull(json['next_lesson_id']),
      );
}

class EnrollmentItem {
  EnrollmentItem({required this.course, required this.enrolledAt, required this.progress, required this.nextLessonId});

  final CourseSummary course;
  final DateTime? enrolledAt;
  final Progress progress;
  final int? nextLessonId;

  factory EnrollmentItem.fromJson(Map<String, dynamic> json) => EnrollmentItem(
        course: CourseSummary.fromJson(jMap(json['course'])),
        enrolledAt: jDate(json['enrolled_at']),
        progress: Progress.fromJson(jMap(json['progress'])),
        nextLessonId: jIntOrNull(json['next_lesson_id']),
      );
}

class PageMeta {
  const PageMeta({required this.page, required this.perPage, required this.total, required this.totalPages});

  final int page;
  final int perPage;
  final int total;
  final int totalPages;

  factory PageMeta.fromJson(Map<String, dynamic> json) => PageMeta(
        page: jInt(json['page'], 1),
        perPage: jInt(json['per_page'], 20),
        total: jInt(json['total']),
        totalPages: jInt(json['total_pages'], 1),
      );

  bool get hasMore => page < totalPages;
}

class CoursePage {
  const CoursePage({required this.items, required this.meta});

  final List<CourseSummary> items;
  final PageMeta meta;
}
