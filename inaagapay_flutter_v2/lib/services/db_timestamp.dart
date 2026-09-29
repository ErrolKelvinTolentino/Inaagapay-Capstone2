// lib/services/db_timestamp.dart

/// Parses a timestamp read from Supabase into the phone's local time.
///
/// Many of this project's `created_at` columns are `timestamp without time
/// zone` filled by `CURRENT_TIMESTAMP`, and the database runs in UTC — so the
/// value is UTC wall-clock time with no zone on the end. `DateTime.parse` reads
/// a zone-less string as *local* time, which put every such time eight hours
/// early in Manila: a checkup recorded at 1:52 PM was listed at 5:52 AM.
///
/// A value that does carry a zone (`Z` or `+08:00`, from a `timestamptz`
/// column) is converted as given — Dart parses either into a UTC DateTime.
DateTime? parseDbTimestamp(Object? value) {
  if (value is DateTime) return value.toLocal();
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  if (parsed.isUtc) return parsed.toLocal();
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  ).toLocal();
}
