import 'package:flutter_test/flutter_test.dart';
import 'package:learnincreation/models/course.dart';
import 'package:learnincreation/models/study_center.dart';
import 'package:learnincreation/models/user.dart';
import 'package:learnincreation/utils/format.dart';
import 'package:learnincreation/utils/validators.dart';

void main() {
  test('formats rupees with Indian grouping', () {
    expect(formatPaise(49900), '₹499');
    expect(formatPaise(49950), '₹499.50');
    expect(formatPaise(250000), '₹2,500');
    expect(formatPaise(15000000), '₹1,50,000');
  });

  test('formats times and dates', () {
    expect(formatTime('16:00'), '4:00 PM');
    expect(formatTime('00:30'), '12:30 AM');
    expect(formatYmd('2026-12-01'), '1 Dec 2026');
    expect(toYmd(DateTime(2026, 3, 7)), '2026-03-07');
  });

  test('validates phone numbers and passwords', () {
    expect(normalizeMobile('+91 98765 43210'), '9876543210');
    expect(normalizeMobile('12345'), isNull);
    expect(validatePassword('short1'), isNotNull);
    expect(validatePassword('letters only'), isNotNull);
    expect(validatePassword('Learn2026x'), isNull);
  });

  test('parses API models defensively', () {
    final course = CourseSummary.fromJson({
      'id': 7,
      'title': 'Python for Beginners',
      'price_paise': 49900,
      'is_free': false,
      'lesson_count': '3',
      'category': {'id': 2, 'name': 'Programming', 'slug': 'programming', 'icon': 'code'},
    });
    expect(course.lessonCount, 3);
    expect(course.category?.icon, 'code');
    expect(course.isBookmarked, isFalse);

    final booking = Booking.fromJson({'id': 1, 'code': 'LCB-ABC123', 'status': 'held', 'seat_label': 'A3'});
    expect(booking.isHeld, isTrue);
    expect(booking.batch, isNull);

    final user = AppUser.fromJson({'id': 1, 'name': 'Asha Rawat', 'has_password': true});
    expect(user.initials, 'AR');
    expect(user.needsName, isFalse);
  });
}
