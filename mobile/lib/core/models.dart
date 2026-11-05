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
  final String author;
  final String caption;
  final String analysis;
  final int step;
  final int savedAt;

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
    this.author = '',
    this.caption = '',
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
        'author': author,
        'caption': caption,
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
        author: j['author'] as String? ?? '',
        caption: j['caption'] as String? ?? '',
        analysis: j['analysis'] as String? ?? 'done',
        step: (j['step'] as num?)?.toInt() ?? 0,
        savedAt: (j['savedAt'] as num?)?.toInt() ?? 0,
        seenAt: (j['seenAt'] as num?)?.toInt() ?? 0,
        archived: j['archived'] == true || j['archived'] == 1,
      );

  Map<String, Object?> toRow() =>
      {...toJson(), 'keyPoints': jsonEncode(keyPoints), 'tags': jsonEncode(tags), 'archived': archived ? 1 : 0};

  factory Reel.fromRow(Map<String, Object?> r) => Reel.fromJson({
        ...r,
        'keyPoints': jsonDecode(r['keyPoints'] as String? ?? '[]'),
        'tags': jsonDecode(r['tags'] as String? ?? '[]'),
      });

  String toMarkdown() => [
        '# $title',
        '',
        '$url · ${author.isEmpty ? app : '@$author'}',
        '',
        summary,
        if (keyPoints.isNotEmpty) ...['', for (final k in keyPoints) '- $k'],
        if (tags.isNotEmpty) ...['', tags.map((t) => '#$t').join(' ')],
        '',
      ].join('\n');

  static List<String> _strings(Object? v) => v is List ? v.map((e) => '$e').toList() : const [];
}
