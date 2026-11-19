import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/course.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/auth_guard.dart';
import '../../utils/messenger.dart';
import '../../widgets/common.dart';
import '../../widgets/course_widgets.dart';
import '../../widgets/loader.dart';
import '../course/lesson_screen.dart';
import '../home/home_tab.dart' show openCourse;
import '../home_shell.dart';

class MyLearningTab extends StatelessWidget {
  const MyLearningTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.isSignedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('My learning')),
        body: EmptyView(
          icon: Icons.play_lesson_outlined,
          title: 'Your courses live here',
          message: 'Sign in to see the courses you enrolled in and the ones you saved.',
          action: FilledButton(
            onPressed: () => ensureSignedIn(context),
            child: const Text('Sign in'),
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My learning'),
          bottom: const TabBar(tabs: [Tab(text: 'My courses'), Tab(text: 'Saved')]),
        ),
        body: TabBarView(
          children: [
            Loader<List<EnrollmentItem>>(
              reloadToken: session.version,
              load: () => CatalogApi(session.api).myEnrollments(),
              builder: (context, items, reload) => items.isEmpty
                  ? EmptyView(
                      icon: Icons.school_outlined,
                      title: 'No courses yet',
                      message: 'Enroll in a course and it will show up here.',
                      action: FilledButton(
                        onPressed: () => HomeShell.of(context)?.openExplore(),
                        child: const Text('Explore courses'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: reload,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: items.length,
                        itemBuilder: (context, index) => _EnrolledTile(item: items[index]),
                      ),
                    ),
            ),
            Loader<List<CourseSummary>>(
              reloadToken: session.version,
              load: () => CatalogApi(session.api).myBookmarks(),
              builder: (context, courses, reload) => courses.isEmpty
                  ? const EmptyView(
                      icon: Icons.bookmark_border,
                      title: 'Nothing saved yet',
                      message: 'Tap the bookmark on any course to save it for later.',
                    )
                  : RefreshIndicator(
                      onRefresh: reload,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: courses.length,
                        itemBuilder: (context, index) {
                          final course = courses[index];
                          return CourseTile(
                            course: course,
                            onTap: () => openCourse(context, course),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.bookmark_remove_outlined),
                              onPressed: () => _removeBookmark(context, course),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeBookmark(BuildContext context, CourseSummary course) async {
    final session = context.read<Session>();
    try {
      await CatalogApi(session.api).setBookmark(course.id, false);
      session.dataChanged();
      showMessage('Removed “${course.title}” from saved.');
    } catch (error) {
      showMessage(errorText(error));
    }
  }
}

class _EnrolledTile extends StatelessWidget {
  const _EnrolledTile({required this.item});

  final EnrollmentItem item;

  @override
  Widget build(BuildContext context) {
    final course = item.course;
    final finished = item.progress.total > 0 && item.progress.completed >= item.progress.total;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: cardDecoration(),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            InkWell(
              onTap: () => openCourse(context, course),
              child: Row(
                children: [
                  SizedBox(width: 84, height: 64, child: CourseThumb(course: course, height: 64, iconSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(course.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: item.progress.fraction,
                minHeight: 7,
                backgroundColor: AppColors.primarySoft,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.progress.total == 0
                        ? 'Lessons coming soon'
                        : '${item.progress.completed} of ${item.progress.total} lessons · ${item.progress.percent}%',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: item.progress.total == 0
                      ? null
                      : () {
                          final next = item.nextLessonId;
                          if (next == null || finished) {
                            openCourse(context, course);
                            return;
                          }
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                LessonScreen(courseId: course.id, lessonId: next, courseTitle: course.title, enrolled: true),
                          ));
                        },
                  child: Text(finished ? 'Review' : (item.progress.completed == 0 ? 'Start' : 'Continue')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
