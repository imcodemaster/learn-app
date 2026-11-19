import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/course.dart';
import '../../services/apis.dart';
import '../../services/payment_flow.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/auth_guard.dart';
import '../../utils/format.dart';
import '../../utils/messenger.dart';
import '../../widgets/common.dart';
import '../../widgets/course_widgets.dart';
import '../../widgets/loader.dart';
import 'lesson_screen.dart';

class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.courseId, this.title});

  final int courseId;
  final String? title;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Loader<CourseDetail>(
      reloadToken: session.version,
      load: () => CatalogApi(session.api).course(widget.courseId),
      frame: (child) => Scaffold(
        appBar: AppBar(title: Text(widget.title ?? 'Course', maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: child,
      ),
      builder: (context, detail, reload) => _content(context, detail, reload),
    );
  }

  Widget _content(BuildContext context, CourseDetail detail, Future<void> Function() reload) {
    final course = detail.summary;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: reload,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 210,
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  tooltip: course.isBookmarked ? 'Remove from saved' : 'Save course',
                  icon: Icon(course.isBookmarked ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: _busy ? null : () => _toggleBookmark(course),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: CourseThumb(course: course, radius: 0, iconSize: 72),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (course.category != null)
                      Text(course.category!.name.toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    Text(course.title,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text)),
                    if (course.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(course.subtitle, style: const TextStyle(fontSize: 15.5, color: AppColors.muted, height: 1.4)),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        InfoChip(icon: Icons.signal_cellular_alt, label: capitalize(course.difficulty)),
                        InfoChip(icon: Icons.translate, label: course.language),
                        if (course.durationLabel.isNotEmpty) InfoChip(icon: Icons.schedule, label: course.durationLabel),
                        InfoChip(
                          icon: Icons.menu_book_outlined,
                          label: course.comingSoon ? 'Lessons coming soon' : plural(course.lessonCount, 'lesson'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (course.isEnrolled && detail.progress != null)
                      _ProgressCard(progress: detail.progress!)
                    else
                      PriceTag(course: course, large: true),
                    if (detail.outcomes.isNotEmpty)
                      _Section(
                        title: 'What you’ll learn',
                        child: Column(
                          children: [
                            for (final outcome in detail.outcomes)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.check_circle_outline, size: 20, color: AppColors.success),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(outcome, style: const TextStyle(height: 1.35))),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (detail.description.isNotEmpty)
                      _Section(
                        title: 'About this course',
                        child: Text(detail.description, style: const TextStyle(height: 1.5, fontSize: 15)),
                      ),
                    _Section(
                      title: 'Course content',
                      child: detail.lessons.isEmpty
                          ? const Text('New lessons are being added. Check back soon!',
                              style: TextStyle(color: AppColors.muted))
                          : _Curriculum(detail: detail, onOpen: (lesson) => _openLesson(detail, lesson)),
                    ),
                    if (detail.requirements.isNotEmpty)
                      _Section(
                        title: 'Requirements',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final requirement in detail.requirements)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('•  $requirement', style: const TextStyle(height: 1.35)),
                              ),
                          ],
                        ),
                      ),
                    if (course.instructorName.isNotEmpty)
                      _Section(
                        title: 'Instructor',
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Avatar(initials: course.instructorName.isNotEmpty ? course.instructorName[0] : 'L'),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(course.instructorName,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                  if (detail.instructorBio.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(detail.instructorBio,
                                        style: const TextStyle(color: AppColors.muted, height: 1.4)),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _ActionBar(
        detail: detail,
        busy: _busy,
        onEnroll: () => _enroll(course),
        onBuy: () => _buy(course),
        onContinue: () {
          final next = detail.nextLesson;
          if (next != null) _openLesson(detail, next);
        },
      ),
    );
  }

  void _openLesson(CourseDetail detail, LessonSummary lesson) {
    if (lesson.isLocked) {
      showMessage(detail.summary.isFree
          ? 'Enroll for free to read this lesson.'
          : 'Buy this course to unlock all lessons.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LessonScreen(
        courseId: detail.summary.id,
        lessonId: lesson.id,
        courseTitle: detail.summary.title,
        enrolled: detail.summary.isEnrolled,
      ),
    ));
  }

  Future<void> _toggleBookmark(CourseSummary course) async {
    if (!await ensureSignedIn(context, reason: 'Sign in to save courses for later.')) return;
    if (!mounted) return;
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      final save = !course.isBookmarked;
      await CatalogApi(session.api).setBookmark(course.id, save);
      course.isBookmarked = save;
      showMessage(save ? 'Saved to My learning.' : 'Removed from saved courses.');
      session.dataChanged();
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enroll(CourseSummary course) async {
    if (!await ensureSignedIn(context, reason: 'Sign in to enroll in this course.')) return;
    if (!mounted) return;
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      await CatalogApi(session.api).enroll(course.id);
      showMessage('You’re enrolled! Start with the first lesson.');
      session.dataChanged();
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(CourseSummary course) async {
    if (!await ensureSignedIn(context, reason: 'Sign in to buy this course.')) return;
    if (!mounted) return;
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      final checkout = await PaymentApi(session.api).courseOrder(course.id);
      if (!mounted) return;
      final result = await PaymentFlow.pay(context, checkout);
      if (result == null) {
        showMessage('Payment cancelled.');
      } else if (result.isPaid) {
        showMessage('Payment successful — the course is yours!');
      } else {
        showMessage(result.message);
      }
      session.dataChanged();
    } on ApiException catch (error) {
      if (error.code == 'already_enrolled') session.dataChanged();
      showMessage(error.message);
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: AppColors.success),
              const SizedBox(width: 8),
              const Expanded(child: Text('You’re enrolled', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('${progress.percent}%', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 8,
              backgroundColor: AppColors.primarySoft,
            ),
          ),
          const SizedBox(height: 6),
          Text('${progress.completed} of ${progress.total} lessons completed',
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Curriculum extends StatelessWidget {
  const _Curriculum({required this.detail, required this.onOpen});

  final CourseDetail detail;
  final ValueChanged<LessonSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? currentSection;
    var number = 0;
    for (final lesson in detail.lessons) {
      if (lesson.sectionTitle.isNotEmpty && lesson.sectionTitle != currentSection) {
        currentSection = lesson.sectionTitle;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(lesson.sectionTitle,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
        ));
      }
      number++;
      final IconData icon;
      final Color color;
      if (lesson.isCompleted) {
        icon = Icons.check_circle;
        color = AppColors.success;
      } else if (lesson.isLocked) {
        icon = Icons.lock_outline;
        color = AppColors.muted;
      } else if (lesson.isFreePreview && !detail.summary.isEnrolled) {
        icon = Icons.visibility_outlined;
        color = AppColors.primary;
      } else {
        icon = Icons.article_outlined;
        color = AppColors.primary;
      }
      children.add(Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: cardDecoration(),
        child: ListTile(
          onTap: () => onOpen(lesson),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text('$number. ${lesson.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text([
            '${lesson.readingMinutes} min read',
            if (lesson.isFreePreview && !detail.summary.isEnrolled) 'Free preview',
          ].join(' · ')),
          trailing: const Icon(Icons.chevron_right),
        ),
      ));
    }
    return Column(children: children);
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.detail,
    required this.busy,
    required this.onEnroll,
    required this.onBuy,
    required this.onContinue,
  });

  final CourseDetail detail;
  final bool busy;
  final VoidCallback onEnroll;
  final VoidCallback onBuy;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final course = detail.summary;
    final String label;
    final VoidCallback? action;
    if (course.isEnrolled) {
      label = detail.lessons.isEmpty ? 'Lessons coming soon' : 'Continue learning';
      action = detail.lessons.isEmpty ? null : onContinue;
    } else if (course.comingSoon && !course.isFree) {
      label = 'Lessons coming soon';
      action = null;
    } else if (course.isFree) {
      label = 'Enroll for free';
      action = onEnroll;
    } else {
      label = 'Buy now · ${formatPaise(course.pricePaise)}';
      action = onBuy;
    }
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: FilledButton(
          onPressed: busy ? null : action,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(label),
        ),
      ),
    );
  }
}
