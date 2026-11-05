import 'dart:convert';

import '../core/models.dart';
import 'library_db.dart';

/// `library.json` content; Import reads the same shape.
String exportJson(List<Reel> reels) =>
    const JsonEncoder.withIndent('  ').convert({'version': 1, 'reels': reels.map((r) => r.toJson()).toList()});

/// `<date>-<title>.md`, safe for Downloads.
String markdownName(Reel r) {
  final d = DateTime.fromMillisecondsSinceEpoch(r.savedAt).toIso8601String().substring(0, 10);
  final t = r.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return '$d-${t.isEmpty ? 'reel' : (t.length > 50 ? t.substring(0, 50) : t)}.md';
}

/// Merges by URL: an item already in the library is left as it is. Returns how many were added.
Future<int> importJson(LibraryDb db, String json) async {
  final data = jsonDecode(json);
  final list = data is Map ? data['reels'] : data;
  if (list is! List) throw const FormatException('Not a Reel Bot library.json');
  var added = 0;
  for (final j in list) {
    final r = Reel.fromJson(Map<String, Object?>.from(j as Map));
    if (await db.has(r.url)) continue;
    await db.saveReel(r);
    added++;
  }
  return added;
}
