/// Notification timestamps — parsing and the relative-time label.
///
/// The backend returns `created_at` as timezone-aware ISO 8601
/// (`2026-10-29T20:07:02.948234+00:00`). Labels are always computed here from
/// that persisted value at render time, so they stay correct as time passes
/// instead of freezing at whatever the server said when the list was fetched.
/// See NOTIFICATION_TIMING_AND_NAVIGATION_AUDIT.md.
library;

final _hasOffset = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$');

/// Parses a notification timestamp to UTC, or null if missing/unparseable.
///
/// An ISO string *without* an offset is treated as UTC, never as the device's
/// local time: the database stores UTC wall-clock, and reading it as local
/// time is exactly what made a brand-new notification read "6 hours ago" in
/// Asia/Dhaka (UTC+6).
DateTime? parseNotificationTimestamp(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  if (_hasOffset.hasMatch(s)) return parsed.toUtc();
  return DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
      parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond);
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Just now / 1 min ago / N mins ago / 1 hour ago / N hours ago / 1 day ago /
/// N days ago / `Sep 22, 2026` for 7+ days (shown in the device's local date).
/// Same rules as the backend's `notifications.serializers.relative_time`.
///
/// Elapsed time is computed between two absolute instants, so the device's
/// timezone and daylight-saving changes cannot shift it. A timestamp slightly
/// in the future (client clock behind the server) reads "Just now".
String formatNotificationTime(DateTime createdAt, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).toUtc().difference(createdAt.toUtc());
  final seconds = elapsed.inSeconds;
  if (seconds < 60) return 'Just now';
  final minutes = elapsed.inMinutes;
  if (minutes < 60) return minutes == 1 ? '1 min ago' : '$minutes mins ago';
  final hours = elapsed.inHours;
  if (hours < 24) return hours == 1 ? '1 hour ago' : '$hours hours ago';
  final days = elapsed.inDays;
  if (days < 7) return days == 1 ? '1 day ago' : '$days days ago';
  final local = createdAt.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

/// The label for one notification row: computed from `created_at` when
/// present, falling back to the server-rendered `time` only for payloads that
/// predate the `created_at` field.
String notificationTimeLabel(Map<String, dynamic> notification, {DateTime? now}) {
  final created = parseNotificationTimestamp(notification['created_at']);
  if (created != null) return formatNotificationTime(created, now: now);
  return notification['time']?.toString() ?? '';
}
