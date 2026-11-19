const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// 49900 → ₹499, 150000000 → ₹15,00,000 (Indian digit grouping).
String formatPaise(int paise) {
  final rupees = paise ~/ 100;
  final rest = paise % 100;
  final grouped = _indianGrouping(rupees);
  return rest == 0 ? '₹$grouped' : '₹$grouped.${rest.toString().padLeft(2, '0')}';
}

String _indianGrouping(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return digits;
  final lastThree = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (head.length > 2) {
    groups.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) groups.insert(0, head);
  return '${groups.join(',')},$lastThree';
}

String formatDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

String formatDateTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '${formatDate(date)}, $hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
}

/// '2026-12-01' → '1 Dec 2026'
String formatYmd(String? ymd) {
  if (ymd == null || ymd.isEmpty) return '';
  final date = DateTime.tryParse(ymd);
  return date == null ? ymd : formatDate(date);
}

/// '16:00' → '4:00 PM'
String formatTime(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}';
}

String formatTimeRange(String start, String end) => '${formatTime(start)} – ${formatTime(end)}';

/// DateTime → '2026-12-01'
String toYmd(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String capitalize(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

String plural(int count, String one, [String? many]) => '$count ${count == 1 ? one : (many ?? '${one}s')}';

String countdown(Duration duration) {
  if (duration.isNegative) return '0:00';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
