import 'package:flutter/material.dart';

import '../models/course.dart';
import '../theme.dart';
import '../utils/format.dart';

IconData categoryIcon(String? name) {
  switch (name) {
    case 'computer':
      return Icons.computer;
    case 'description':
      return Icons.description_outlined;
    case 'web':
      return Icons.language;
    case 'code':
      return Icons.code;
    case 'campaign':
      return Icons.campaign_outlined;
    case 'dns':
      return Icons.dns_outlined;
    default:
      return Icons.school_outlined;
  }
}

const _gradients = <List<Color>>[
  [Color(0xFF4338CA), Color(0xFF6366F1)],
  [Color(0xFF0F766E), Color(0xFF14B8A6)],
  [Color(0xFFB45309), Color(0xFFF59E0B)],
  [Color(0xFF9D174D), Color(0xFFEC4899)],
  [Color(0xFF1D4ED8), Color(0xFF38BDF8)],
  [Color(0xFF6D28D9), Color(0xFFA78BFA)],
];

/// Course image, or a coloured placeholder with the category icon.
class CourseThumb extends StatelessWidget {
  const CourseThumb({super.key, required this.course, this.height, this.radius = 14, this.iconSize = 40});

  final CourseSummary course;
  final double? height;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[course.id % _gradients.length];
    final placeholder = Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Icon(categoryIcon(course.category?.icon), color: Colors.white.withValues(alpha: 0.92), size: iconSize),
    );
    final url = course.thumbnailUrl;
    final Widget image = url == null
        ? placeholder
        : Image.network(
            url,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          );
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.course, this.large = false});

  final CourseSummary course;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 22.0 : 15.0;
    if (course.isFree) {
      return Text('Free', style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: AppColors.success));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(formatPaise(course.pricePaise),
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: AppColors.text)),
        if (course.mrpPaise > course.pricePaise) ...[
          const SizedBox(width: 6),
          Text(
            formatPaise(course.mrpPaise),
            style: TextStyle(
              fontSize: size * 0.7,
              color: AppColors.muted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      ],
    );
  }
}

/// Vertical card for horizontal carousels.
class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course, required this.onTap, this.width = 250});

  final CourseSummary course;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: cardDecoration(),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CourseThumb(course: course, height: 120),
                const SizedBox(height: 10),
                Text(course.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text)),
                const SizedBox(height: 4),
                Text(
                  course.comingSoon ? 'Lessons coming soon' : plural(course.lessonCount, 'lesson'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(child: PriceTag(course: course)),
                    if (course.isEnrolled)
                      const Icon(Icons.check_circle, color: AppColors.success, size: 20)
                    else if (course.isBookmarked)
                      const Icon(Icons.bookmark, color: AppColors.primary, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Row layout for lists.
class CourseTile extends StatelessWidget {
  const CourseTile({super.key, required this.course, required this.onTap, this.trailing});

  final CourseSummary course;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: cardDecoration(),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(width: 96, height: 76, child: CourseThumb(course: course, height: 76, iconSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(course.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text)),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (course.category != null) course.category!.name,
                          course.comingSoon ? 'Coming soon' : plural(course.lessonCount, 'lesson'),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 6),
                      course.isEnrolled
                          ? const Text('Enrolled',
                              style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))
                          : PriceTag(course: course),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
