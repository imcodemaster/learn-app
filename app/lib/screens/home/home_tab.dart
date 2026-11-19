import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/course_widgets.dart';
import '../../widgets/loader.dart';
import '../course/course_detail_screen.dart';
import '../course/lesson_screen.dart';
import '../home_shell.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final catalog = CatalogApi(session.api);
    return Scaffold(
      body: SafeArea(
        child: Loader<_HomeData>(
          reloadToken: session.version,
          load: () => _HomeData.load(catalog, session.isSignedIn),
          builder: (context, data, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                const _Header(),
                const _SearchBox(),
                const _Hero(),
                if (data.enrollments.isNotEmpty) ...[
                  const SectionHeader(title: 'Continue learning'),
                  SizedBox(
                    height: 150,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: data.enrollments.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) => _ContinueCard(item: data.enrollments[index]),
                    ),
                  ),
                ],
                if (data.categories.isNotEmpty) ...[
                  const SectionHeader(title: 'Categories'),
                  SizedBox(
                    height: 46,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: data.categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final category = data.categories[index];
                        return ActionChip(
                          avatar: Icon(categoryIcon(category.icon), size: 18, color: AppColors.primary),
                          label: Text(category.name),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: AppColors.border),
                          onPressed: () => HomeShell.of(context)?.openExplore(category: category.slug),
                        );
                      },
                    ),
                  ),
                ],
                if (data.featured.isNotEmpty) ...[
                  SectionHeader(
                    title: 'Featured courses',
                    actionLabel: 'See all',
                    onAction: () => HomeShell.of(context)?.openExplore(),
                  ),
                  SizedBox(
                    height: 262,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: data.featured.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final course = data.featured[index];
                        return CourseCard(course: course, onTap: () => openCourse(context, course));
                      },
                    ),
                  ),
                ],
                const _StudyCenterPromo(),
                if (data.popular.isNotEmpty) ...[
                  SectionHeader(
                    title: 'Popular courses',
                    actionLabel: 'Explore',
                    onAction: () => HomeShell.of(context)?.openExplore(),
                  ),
                  for (final course in data.popular)
                    CourseTile(course: course, onTap: () => openCourse(context, course)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void openCourse(BuildContext context, CourseSummary course) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CourseDetailScreen(courseId: course.id, title: course.title),
  ));
}

class _HomeData {
  _HomeData(this.categories, this.featured, this.popular, this.enrollments);

  final List<CourseCategory> categories;
  final List<CourseSummary> featured;
  final List<CourseSummary> popular;
  final List<EnrollmentItem> enrollments;

  static Future<_HomeData> load(CatalogApi catalog, bool signedIn) async {
    final results = await Future.wait<Object>([
      catalog.categories(),
      catalog.courses(featured: true, perPage: 10),
      catalog.courses(sort: 'popular', perPage: 8),
      if (signedIn) catalog.myEnrollments(),
    ]);
    return _HomeData(
      results[0] as List<CourseCategory>,
      (results[1] as CoursePage).items,
      (results[2] as CoursePage).items,
      signedIn ? results[3] as List<EnrollmentItem> : <EnrollmentItem>[],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user == null ? 'Welcome 👋' : 'Hi, ${user.firstName} 👋',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text),
                ),
                const SizedBox(height: 2),
                Text(session.info.tagline, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => HomeShell.of(context)?.openTab(HomeShellState.account),
            child: user == null
                ? const CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primarySoft,
                    child: Icon(Icons.person_outline, color: AppColors.primary),
                  )
                : Avatar(initials: user.initials, imageUrl: user.avatarUrl, radius: 22),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => HomeShell.of(context)?.openExplore(focusSearch: true),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: cardDecoration(),
            child: const Row(
              children: [
                Icon(Icons.search, color: AppColors.muted),
                SizedBox(width: 12),
                Text('What do you want to learn today?', style: TextStyle(color: AppColors.muted, fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final info = context.watch<Session>().info;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
            child: const Text('Computer & coding courses',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.text)),
          ),
          const SizedBox(height: 14),
          Text(info.heroTitle,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 8),
          const Text('Short text lessons, practice tasks and classroom batches in Rudrapur.',
              style: TextStyle(color: Color(0xFFE0E7FF), height: 1.4)),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => HomeShell.of(context)?.openExplore(),
            child: const Text('Explore courses'),
          ),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item});

  final EnrollmentItem item;

  @override
  Widget build(BuildContext context) {
    final course = item.course;
    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            final next = item.nextLessonId;
            if (next == null) {
              openCourse(context, course);
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LessonScreen(courseId: course.id, lessonId: next, courseTitle: course.title, enrolled: true),
              ));
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: cardDecoration(),
            child: Row(
              children: [
                SizedBox(width: 70, height: 70, child: CourseThumb(course: course, height: 70, iconSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(course.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: item.progress.fraction,
                          minHeight: 7,
                          backgroundColor: AppColors.primarySoft,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('${item.progress.completed}/${item.progress.total} lessons · ${item.progress.percent}%',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudyCenterPromo extends StatelessWidget {
  const _StudyCenterPromo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Material(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => HomeShell.of(context)?.openTab(HomeShellState.studyCenter),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.accent,
                  child: Icon(Icons.event_seat, color: Colors.white),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LearnInCreation Study Center',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text)),
                      SizedBox(height: 4),
                      Text('Book your seat in a classroom batch or rent a library desk in Rudrapur.',
                          style: TextStyle(color: AppColors.muted, height: 1.35)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
