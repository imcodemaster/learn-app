import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/course.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/links.dart';
import '../../utils/messenger.dart';
import '../../widgets/loader.dart';

/// Reads one text lesson (Markdown) with previous/next and "mark complete".
class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.courseId,
    required this.lessonId,
    required this.courseTitle,
    required this.enrolled,
  });

  final int courseId;
  final int lessonId;
  final String courseTitle;
  final bool enrolled;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    return Scaffold(
      appBar: AppBar(title: Text(widget.courseTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Loader<LessonDetail>(
        load: () => CatalogApi(api).lesson(widget.courseId, widget.lessonId),
        builder: (context, lesson, reload) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  if (lesson.sectionTitle.isNotEmpty)
                    Text(lesson.sectionTitle.toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Text(lesson.title,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.2)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 16, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Text('${lesson.readingMinutes} min read', style: const TextStyle(color: AppColors.muted)),
                      if (lesson.isCompleted) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                        const SizedBox(width: 4),
                        const Text('Completed', style: TextStyle(color: AppColors.success)),
                      ],
                    ],
                  ),
                  const Divider(height: 32),
                  MarkdownBody(
                    data: lesson.contentMd,
                    selectable: true,
                    styleSheet: _markdownStyle(context),
                    onTapLink: (text, href, title) {
                      if (href != null) openLink(href);
                    },
                  ),
                ],
              ),
            ),
            _BottomBar(
              lesson: lesson,
              canTrack: widget.enrolled,
              busy: _busy,
              onToggleComplete: () => _toggleComplete(lesson),
              onOpen: _openLesson,
            ),
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: const TextStyle(fontSize: 16.5, height: 1.65, color: Color(0xFF1F2937)),
      h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text),
      h2: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.6),
      h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.6),
      listBullet: const TextStyle(fontSize: 16.5, height: 1.6),
      code: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: Color(0xFF3730A3),
        backgroundColor: Color(0xFFEEF2FF),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: AppColors.primary, width: 4)),
      ),
      tableBorder: TableBorder.all(color: AppColors.border),
      tableHead: const TextStyle(fontWeight: FontWeight.w700),
      tableCellsPadding: const EdgeInsets.all(8),
      a: const TextStyle(color: AppColors.primary, decoration: TextDecoration.underline),
    );
  }

  void _openLesson(int lessonId) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LessonScreen(
        courseId: widget.courseId,
        lessonId: lessonId,
        courseTitle: widget.courseTitle,
        enrolled: widget.enrolled,
      ),
    ));
  }

  Future<void> _toggleComplete(LessonDetail lesson) async {
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      final done = !lesson.isCompleted;
      final progress = await CatalogApi(session.api).setCompleted(lesson.id, done);
      if (!mounted) return;
      setState(() => lesson.isCompleted = done);
      session.dataChanged();
      if (done) {
        final next = lesson.nextLessonId;
        showMessage(
          progress.percent >= 100 ? 'Course complete — well done! 🎉' : 'Lesson completed (${progress.percent}% done).',
          action: next == null ? null : SnackBarAction(label: 'Next lesson', onPressed: () => _openLesson(next)),
        );
      }
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.lesson,
    required this.canTrack,
    required this.busy,
    required this.onToggleComplete,
    required this.onOpen,
  });

  final LessonDetail lesson;
  final bool canTrack;
  final bool busy;
  final VoidCallback onToggleComplete;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final prev = lesson.prevLessonId;
    final next = lesson.nextLessonId;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            IconButton.outlined(
              tooltip: 'Previous lesson',
              onPressed: prev == null ? null : () => onOpen(prev),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: canTrack
                  ? FilledButton.icon(
                      onPressed: busy ? null : onToggleComplete,
                      icon: Icon(lesson.isCompleted ? Icons.undo : Icons.check),
                      label: Text(lesson.isCompleted ? 'Mark as not done' : 'Mark as complete'),
                    )
                  : const Text('Free preview', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Next lesson',
              onPressed: next == null ? null : () => onOpen(next),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ),
    );
  }
}
