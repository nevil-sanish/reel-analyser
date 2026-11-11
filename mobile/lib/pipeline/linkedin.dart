import 'dart:convert';

/// LinkedIn posts (1.2.0.0, both builds). A public post's page, fetched without any login, carries the post as schema.org
/// JSON-LD (`SocialMediaPosting`, `VideoObject` or `Article`): its full text, author, pictures and, for a video, a direct mp4
/// link on LinkedIn's media host. This is the same public data a search engine sees. Nothing is fetched with an account, and
/// a post that needs a login (not public) is simply not readable.
class LinkedInPost {
  final String author;
  final String text;
  final List<String> images;
  final String videoUrl;
  final String thumbnail;
  const LinkedInPost({this.author = '', this.text = '', this.images = const [], this.videoUrl = '', this.thumbnail = ''});

  bool get isEmpty => text.isEmpty && images.isEmpty && videoUrl.isEmpty;
}

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
  var author = '', text = '', video = '', thumb = '';
  final images = <String>[];
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
    if (video.isEmpty) video = _urls(j['contentUrl']).where(isLinkedInMedia).firstOrNull ?? '';
    if (thumb.isEmpty) thumb = _urls(j['thumbnailUrl']).where(isLinkedInMedia).firstOrNull ?? '';
    for (final u in _urls(j['image'])) {
      if (isLinkedInMedia(u) && !images.contains(u) && !u.contains('company-logo') && !u.contains('profile-')) images.add(u);
    }
  }
  if (text.isEmpty) text = _meta(html, 'og:description');
  if (text.isEmpty) text = _meta(html, 'og:title');
  if (images.isEmpty && video.isEmpty) {
    final og = _meta(html, 'og:image');
    // The generic LinkedIn logo is on static.licdn.com; a post's own picture is on media.licdn.com.
    if (isLinkedInMedia(og) && og.contains('media.licdn.com')) images.add(og);
  }
  if (author.isEmpty) {
    final t = _meta(html, 'og:title');
    final bar = t.lastIndexOf(' | ');
    if (bar > 0) author = t.substring(bar + 3).split(' | ').first.trim();
  }
  return LinkedInPost(author: author, text: text, images: images.take(10).toList(), videoUrl: video, thumbnail: thumb);
}
