// Small, forgiving JSON readers so one unexpected value never crashes a screen.

int jInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? jIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String jStr(Object? value, [String fallback = '']) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

String? jStrOrNull(Object? value) => (value is String && value.isNotEmpty) ? value : null;

bool jBool(Object? value) => value == true;

Map<String, dynamic> jMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> jList(Object? value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.map((item) => jMap(item)).toList();
}

List<String> jStrings(Object? value) {
  if (value is! List) return <String>[];
  return value.map((item) => jStr(item)).where((s) => s.isNotEmpty).toList();
}

DateTime? jDate(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;
