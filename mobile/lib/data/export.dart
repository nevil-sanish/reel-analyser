import 'dart:convert';

import '../core/models.dart';
import 'library_db.dart';

/// `library.json` content; Import reads the same shape. Version 2 adds saved chats.
String exportJson(List<Reel> reels, [List<(int, String, int, List<String>)> chats = const [], Map<String, Object?>? encryptedKeys]) =>
    const JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'encryptedKeys': ?encryptedKeys,
      'reels': reels.map((r) => r.toJson()).toList(),
      'chats': [for (final (_, title, updatedAt, turns) in chats) {'title': title, 'updatedAt': updatedAt, 'turns': turns}],
    });

/// `<date>-<title>.md`, safe for Downloads.
String markdownName(Reel r) {
  final d = DateTime.fromMillisecondsSinceEpoch(r.savedAt).toIso8601String().substring(0, 10);
  final t = r.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return '$d-${t.isEmpty ? 'reel' : (t.length > 50 ? t.substring(0, 50) : t)}.md';
}

/// The encrypted keys block of a backup file, or null when it has none.
Map<String, Object?>? encryptedKeysOf(String json) {
  final data = jsonDecode(json);
  final k = data is Map ? data['encryptedKeys'] : null;
  return k is Map ? Map<String, Object?>.from(k) : null;
}

/// Merges notes by URL and chats by (first question, last update): what's already here is left as it is.
/// Returns how many notes and chats were added.
Future<(int, int)> importJson(LibraryDb db, String json) async {
  final data = jsonDecode(json);
  final list = data is Map ? data['reels'] : data;
  if (list is! List) throw const FormatException('Not a Reel Analyser library.json');
  var notes = 0;
  for (final j in list) {
    final r = Reel.fromJson(Map<String, Object?>.from(j as Map));
    if (await db.has(r.url)) continue;
    await db.saveReel(r);
    notes++;
  }
  final have = {for (final (_, title, updatedAt, _) in await db.chats()) (title, updatedAt)};
  var chats = 0;
  for (final c in data is Map && data['chats'] is List ? data['chats'] as List : const []) {
    final turns = [for (final t in (c as Map)['turns'] as List) '$t'];
    final key = (c['title'] as String, c['updatedAt'] as int);
    if (turns.isEmpty || !have.add(key)) continue;
    await db.saveChat(null, turns, key.$2);
    chats++;
  }
  return (notes, chats);
}
