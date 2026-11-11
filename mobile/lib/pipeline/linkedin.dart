import 'dart:convert';

import 'gemini.dart';

/// LinkedIn posts (1.2.0.0, both builds). A public post's page, fetched without any login, carries the post as schema.org
/// JSON-LD (`SocialMediaPosting`, `VideoObject` or `Article`): its full text, author, pictures and, for a video, a direct mp4
/// link on LinkedIn's media host. This is the same public data a search engine sees. Nothing is fetched with an account, and
/// a post that needs a login (not public) is simply not readable.
class LinkedInPost {
  final String author;
  final String text;
  final List<String> images;

  /// Every video of the post, in order (most posts have none or one).
  final List<String> videos;
  final String thumbnail;
  const LinkedInPost({this.author = '', this.text = '', this.images = const [], this.videos = const [], this.thumbnail = ''});

  String get videoUrl => videos.isEmpty ? '' : videos.first;
  bool get isEmpty => text.isEmpty && images.isEmpty && videos.isEmpty;
}

/// The most of each kind a post is analysed with.
const maxLinkedInVideos = 3;
const maxLinkedInImages = 10;

/// A desktop-class mobile browser, as a logged-out visitor.
const linkedInUserAgent =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

/// Only links on these hosts are fetched; media only from LinkedIn's own media hosts.
bool isLinkedInHost(String host) {
  final h = host.toLowerCase();
  return h == 'lnkd.in' || h == 'linkedin.com' || h.endsWith('.linkedin.com');
}

bool isLinkedInMedia(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https') return false;
  final h = u.host.toLowerCase();
  return h == 'licdn.com' || h.endsWith('.licdn.com');
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

String _meta(String html, String prop) {
  final m = RegExp('<meta[^>]+(?:property|name)="$prop"[^>]+content="([^"]*)"').firstMatch(html) ??
      RegExp('<meta[^>]+content="([^"]*)"[^>]+(?:property|name)="$prop"').firstMatch(html);
  return m == null ? '' : _unescape(m.group(1)!).trim();
}

List<String> _urls(Object? v) => switch (v) {
      String s => [s],
      Map m => [if (m['url'] is String) m['url'] as String, if (m['contentUrl'] is String) m['contentUrl'] as String],
      List l => [for (final e in l) ..._urls(e)],
      _ => const [],
    };

String _name(Object? v) => switch (v) {
      Map m when m['name'] is String => (m['name'] as String).trim(),
      List l when l.isNotEmpty => _name(l.first),
      _ => '',
    };

/// Reads a public post page. Fields it cannot find stay empty.
LinkedInPost parseLinkedIn(String html) {
  var author = '', text = '', thumb = '';
  final images = <String>[], videos = <String>[];
  void addVideo(Object? v) {
    for (final u in _urls(v)) {
      if (isLinkedInMedia(u) && !videos.contains(u)) videos.add(u);
    }
  }

  for (final m in RegExp(r'<script type="application/ld\+json">(.*?)</script>', dotAll: true).allMatches(html)) {
    Object? j;
    try {
      j = jsonDecode(m.group(1)!);
    } on FormatException {
      continue;
    }
    if (j is! Map) continue;
    final type = '${j['@type']}';
    if (!const {'SocialMediaPosting', 'VideoObject', 'Article', 'NewsArticle', 'BlogPosting'}.contains(type)) continue;
    final body = [j['articleBody'], j['description'], j['text'], j['headline']].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty);
    if (text.isEmpty && body.isNotEmpty) text = body.reduce((a, b) => a.length >= b.length ? a : b);
    if (author.isEmpty) author = _name(j['author']).isNotEmpty ? _name(j['author']) : _name(j['creator']);
    addVideo(j['contentUrl']);
    // A post can also carry its videos as nested VideoObjects.
    for (final v in [j['video'], j['associatedMedia']].expand((v) => v is List ? v : [v])) {
      if (v is Map && '${v['@type']}' == 'VideoObject') {
        addVideo(v['contentUrl']);
        if (thumb.isEmpty) thumb = _urls(v['thumbnailUrl']).where(isLinkedInMedia).firstOrNull ?? '';
      }
    }
    if (thumb.isEmpty) thumb = _urls(j['thumbnailUrl']).where(isLinkedInMedia).firstOrNull ?? '';
    for (final u in _urls(j['image'])) {
      if (isLinkedInMedia(u) && !images.contains(u) && !u.contains('company-logo') && !u.contains('profile-') && !u.contains('videocover')) {
        images.add(u);
      }
    }
  }
  if (text.isEmpty) text = _meta(html, 'og:description');
  if (text.isEmpty) text = _meta(html, 'og:title');
  if (images.isEmpty && videos.isEmpty) {
    final og = _meta(html, 'og:image');
    // The generic LinkedIn logo is on static.licdn.com; a post's own picture is on media.licdn.com.
    if (isLinkedInMedia(og) && og.contains('media.licdn.com')) images.add(og);
  }
  if (author.isEmpty) {
    final t = _meta(html, 'og:title');
    final bar = t.lastIndexOf(' | ');
    if (bar > 0) author = t.substring(bar + 3).split(' | ').first.trim();
  }
  return LinkedInPost(
      author: author,
      text: text,
      images: images.take(maxLinkedInImages).toList(),
      videos: videos.take(maxLinkedInVideos).toList(),
      thumbnail: thumb);
}

/// One note from several parts of a post (its pictures and each video), each already analysed with the post text as context.
/// No extra AI call: titles and summaries come from the parts, lists are joined without repeats, and transcripts keep a heading
/// per part so nothing said in any video is lost.
Analysis mergeAnalyses(List<(String, Analysis)> parts) {
  if (parts.length == 1) return parts.single.$2;
  List<String> union(Iterable<String> xs, int max) {
    final out = <String>[], seen = <String>{};
    for (final x in xs) {
      final k = x.trim().toLowerCase();
      if (k.isEmpty || !seen.add(k)) continue;
      out.add(x.trim());
      if (out.length == max) break;
    }
    return out;
  }

  String joined(String Function(Analysis) f) =>
      [for (final (label, a) in parts) if (f(a).trim().isNotEmpty) '$label:\n${f(a).trim()}'].join('\n\n');
  final as = [for (final (_, a) in parts) a];
  return Analysis(
    as.map((a) => a.title.trim()).firstWhere((t) => t.isNotEmpty, orElse: () => ''),
    [for (final (label, a) in parts) if (a.summary.trim().isNotEmpty) '$label: ${a.summary.trim()}'].join('\n\n'),
    union(as.expand((a) => a.keyPoints), 12),
    union(as.expand((a) => a.tags), 10),
    overview: union(as.expand((a) => a.overview), 12),
    mentions: union(as.expand((a) => a.mentions), 20),
    transcript: joined((a) => a.transcript),
    onScreenText: joined((a) => a.onScreenText),
  );
}
