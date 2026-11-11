import 'dart:convert';

/// One analysed item in the library. `analysis` is how it was summarised:
/// `done` (full video), `caption+thumbnail`, or `text-only`.
class Reel {
  final String url;
  final String app;
  final String title;
  final String summary;
  final List<String> keyPoints;
  final List<String> tags;

  /// v0.9.2: the at-a-glance bullets and the names/tools mentioned. Empty on older notes.
  final List<String> overview;
  final List<String> mentions;
  final String author;
  final String caption;

  /// v0.9.6: the speech word for word and all on-screen text. Empty on older notes and on frame-only notes.
  final String transcript;
  final String onScreenText;
  final String analysis;
  final int step;
  final int savedAt;

  /// Library filter: `reel` (Instagram reel), `post` (Instagram photo post), `short` (YouTube), `photo` (shared picture).
  String get kind => switch (app) {
        'youtube' => 'short',
        'photo' => 'photo',
        _ => url.contains('instagram.com/p/') ? 'post' : 'reel',
      };

  /// When the note was first opened; 0 = unseen (the library shows a dot).
  final int seenAt;
  final bool archived;

  const Reel({
    required this.url,
    required this.app,
    required this.title,
    required this.summary,
    this.keyPoints = const [],
    this.tags = const [],
    this.overview = const [],
    this.mentions = const [],
    this.author = '',
    this.caption = '',
    this.transcript = '',
    this.onScreenText = '',
    this.analysis = 'done',
    this.step = 0,
    required this.savedAt,
    this.seenAt = 0,
    this.archived = false,
  });

  Map<String, Object?> toJson() => {
        'url': url,
        'app': app,
        'title': title,
        'summary': summary,
        'keyPoints': keyPoints,
        'tags': tags,
        'overview': overview,
        'mentions': mentions,
        'author': author,
        'caption': caption,
        'transcript': transcript,
        'onScreenText': onScreenText,
        'analysis': analysis,
        'step': step,
        'savedAt': savedAt,
        'seenAt': seenAt,
        'archived': archived,
      };

  factory Reel.fromJson(Map<String, Object?> j) => Reel(
        url: j['url'] as String,
        app: j['app'] as String? ?? '',
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        keyPoints: _strings(j['keyPoints']),
        tags: _strings(j['tags']),
        overview: _strings(j['overview']),
        mentions: _strings(j['mentions']),
        author: j['author'] as String? ?? '',
        caption: j['caption'] as String? ?? '',
        transcript: j['transcript'] as String? ?? '',
        onScreenText: j['onScreenText'] as String? ?? '',
        analysis: j['analysis'] as String? ?? 'done',
        step: (j['step'] as num?)?.toInt() ?? 0,
        savedAt: (j['savedAt'] as num?)?.toInt() ?? 0,
        seenAt: (j['seenAt'] as num?)?.toInt() ?? 0,
        archived: j['archived'] == true || j['archived'] == 1,
      );

  Map<String, Object?> toRow() =>
      {
        ...toJson(),
        'keyPoints': jsonEncode(keyPoints),
        'tags': jsonEncode(tags),
        'overview': jsonEncode(overview),
        'mentions': jsonEncode(mentions),
        'archived': archived ? 1 : 0,
      };

  factory Reel.fromRow(Map<String, Object?> r) => Reel.fromJson({
        ...r,
        'keyPoints': jsonDecode(r['keyPoints'] as String? ?? '[]'),
        'tags': jsonDecode(r['tags'] as String? ?? '[]'),
        'overview': jsonDecode(r['overview'] as String? ?? '[]'),
        'mentions': jsonDecode(r['mentions'] as String? ?? '[]'),
      });

  String toMarkdown() => [
        '# $title',
        '',
        '$url · ${author.isEmpty ? app : '@$author'}',
        '',
        if (overview.isNotEmpty) ...[for (final o in overview) '- $o', ''],
        summary,
        if (keyPoints.isNotEmpty) ...['', '## Key points', for (final k in keyPoints) '- $k'],
        if (mentions.isNotEmpty) ...['', '## Mentioned', mentions.join(', ')],
        if (transcript.isNotEmpty) ...['', '## Transcript', transcript],
        if (onScreenText.isNotEmpty) ...['', '## On-screen text', onScreenText],
        if (caption.isNotEmpty) ...['', '## Caption', caption],
        if (tags.isNotEmpty) ...['', tags.map((t) => '#$t').join(' ')],
        '',
      ].join('\n');

  /// The note as plain text for the share sheet: the analysis and the link it came from (not the long transcript).
  String toShareText() => [
        title,
        if (app != 'photo') url,
        '',
        if (overview.isNotEmpty) ...[for (final o in overview) '• $o', ''],
        summary,
        if (keyPoints.isNotEmpty) ...['', 'Key points:', for (final k in keyPoints) '• $k'],
        if (mentions.isNotEmpty) ...['', 'Mentioned: ${mentions.join(', ')}'],
        '',
        'Shared from Reel Analyser',
      ].join('\n');

  static List<String> _strings(Object? v) => v is List ? v.map((e) => '$e').toList() : const [];
}

/// A folder of notes. Every note is also in All, which is not a row.
class Folder {
  final int id;
  final String name;
  const Folder(this.id, this.name);
}

/// A note's link may come from an imported file, so only Instagram and YouTube https links are ever opened.
bool isReelLink(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https') return false;
  final h = u.host.toLowerCase();
  return h == 'instagram.com' || h.endsWith('.instagram.com') || h == 'youtube.com' || h.endsWith('.youtube.com') || h == 'youtu.be';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Card label for when a note was saved: "just now", "5m ago", "3h ago", "yesterday", "3 Nov", "3 Nov 2025".
String savedAgo(int ms, DateTime now) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  final today = DateTime(now.year, now.month, now.day);
  if (!t.isBefore(today)) return '${d.inHours}h ago';
  if (!t.isBefore(today.subtract(const Duration(days: 1)))) return 'yesterday';
  return '${t.day} ${_months[t.month - 1]}${t.year == now.year ? '' : ' ${t.year}'}';
}

/// Note screen: "Saved 6 Nov 2026, 14:05".
String savedOn(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Saved ${t.day} ${_months[t.month - 1]} ${t.year}, ${two(t.hour)}:${two(t.minute)}';
}
