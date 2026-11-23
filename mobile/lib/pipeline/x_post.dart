import 'dart:convert';

/// X (Twitter) posts (1.2.4.0, both builds). X's own embed endpoint (`cdn.syndication.twimg.com/tweet-result`, the one the
/// "Embed this post" widget on any website uses) answers a public post's id without a login, an account or an API key.
/// Nothing goes through a third party. A deleted, private or age-restricted post answers with a "tombstone" and is simply
/// not readable.
class XPost {
  final String author;
  final String text;
  final List<String> images;

  /// The best mp4 of the post's video (highest resolution), empty when there is none.
  final String videoUrl;
  final String thumbnail;

  /// True when X answered but would not show the post (deleted, private, restricted).
  final bool unavailable;
  const XPost({this.author = '', this.text = '', this.images = const [], this.videoUrl = '', this.thumbnail = '', this.unavailable = false});

  bool get isEmpty => text.isEmpty && images.isEmpty && videoUrl.isEmpty;
}

const maxXImages = 4;

/// Only links on these hosts are read.
bool isXHost(String host) {
  final h = host.toLowerCase();
  return h == 'x.com' || h == 'twitter.com' || h.endsWith('.x.com') || h.endsWith('.twitter.com');
}

/// Pictures and videos come from X's own media hosts only.
bool isXMedia(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https') return false;
  final h = u.host.toLowerCase();
  return h == 'twimg.com' || h.endsWith('.twimg.com');
}

/// The post's number, from `.../status/<id>` or `.../i/web/status/<id>`.
String? xPostId(Uri u) => RegExp(r'/status(?:es)?/(\d{5,25})').firstMatch(u.path)?.group(1);

/// The embed endpoint's answer for [id]. The token is not checked by X, any short value is accepted.
Uri xSyndicationUrl(String id) => Uri.parse('https://cdn.syndication.twimg.com/tweet-result?id=$id&lang=en&token=a');

/// Resolution written into the mp4's path (`.../1280x720/...`); 0 when absent.
int _pixels(String url) {
  final m = RegExp(r'/(\d{2,5})x(\d{2,5})/').firstMatch(url);
  return m == null ? 0 : int.parse(m.group(1)!) * int.parse(m.group(2)!);
}

/// Reads the embed endpoint's JSON. Fields it cannot find stay empty.
XPost parseXPost(String body) {
  Object? j;
  try {
    j = jsonDecode(body);
  } on FormatException {
    return const XPost();
  }
  if (j is! Map) return const XPost();
  if ('${j['__typename']}' == 'TweetTombstone') return const XPost(unavailable: true);

  final user = j['user'];
  final handle = user is Map ? '${user['screen_name'] ?? ''}' : '';
  final name = user is Map ? '${user['name'] ?? ''}'.trim() : '';
  final author = name.isNotEmpty && handle.isNotEmpty ? '$name (@$handle)' : (handle.isNotEmpty ? '@$handle' : name);

  var text = '${j['text'] ?? ''}'.trim();
  // The text ends with the t.co link to the post's own media; drop it, the media is analysed separately.
  text = text.replaceAll(RegExp(r'\s*https://t\.co/\w+\s*$'), '').trim();

  final images = <String>[];
  for (final p in j['photos'] is List ? j['photos'] as List : const []) {
    final u = p is Map ? '${p['url'] ?? ''}' : '';
    if (isXMedia(u) && !images.contains(u)) images.add(u);
  }
  var video = '', thumb = '';
  final v = j['video'];
  if (v is Map) {
    final poster = '${v['poster'] ?? ''}';
    if (isXMedia(poster)) thumb = poster;
    var bestPixels = -1;
    for (final e in v['variants'] is List ? v['variants'] as List : const []) {
      if (e is! Map) continue;
      final src = '${e['src'] ?? ''}';
      if ('${e['type']}' != 'video/mp4' || !isXMedia(src)) continue;
      if (_pixels(src) > bestPixels) {
        bestPixels = _pixels(src);
        video = src;
      }
    }
  }
  return XPost(
    author: author,
    text: text,
    images: images.take(maxXImages).toList(),
    videoUrl: video,
    thumbnail: thumb,
  );
}
