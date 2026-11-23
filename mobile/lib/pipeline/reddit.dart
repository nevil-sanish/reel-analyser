import 'dart:convert';

/// Reddit posts (both builds). Reddit shows a post to a logged-out app nowhere: the `.json`, `.rss` and old.reddit pages all
/// answer 403 or 429. First the free public Arctic Shift archive is asked for the post id (no login, no key); a post newer than
/// about an hour may not be there yet. Then, with the user's own Apify key (kept on the phone, sent in a header), Apify.
class RedditPost {
  final String author;
  final String subreddit;
  final String title;
  final String body;
  final List<String> images;
  final String videoUrl;
  const RedditPost({this.author = '', this.subreddit = '', this.title = '', this.body = '', this.images = const [], this.videoUrl = ''});

  bool get isEmpty => title.isEmpty && body.isEmpty && images.isEmpty && videoUrl.isEmpty;
}

const maxRedditImages = 6;

/// The Apify actor used, and what it is sent for one post.
const redditActor = 'trudax~reddit-scraper-lite';

Map<String, Object?> redditActorInput(String url) => {
      'startUrls': [
        {'url': url},
      ],
      'includeMediaLinks': true,
      'skipComments': true,
      'maxItems': 1,
    };

bool isRedditHost(String host) {
  final h = host.toLowerCase();
  return h == 'reddit.com' || h.endsWith('.reddit.com') || h == 'redd.it';
}

/// Media only from Reddit's own hosts.
bool isRedditMedia(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https') return false;
  final h = u.host.toLowerCase();
  return h == 'redd.it' || h.endsWith('.redd.it') || h == 'redditmedia.com' || h.endsWith('.redditmedia.com') || h == 'redditstatic.com';
}

List<String> _strs(Object? v) => v is List ? [for (final e in v) if (e is String && isRedditMedia(e)) e] : const [];

/// The first post of the actor's dataset (comments, if any, are ignored).
RedditPost parseRedditItems(String body) {
  Object? j;
  try {
    j = jsonDecode(body);
  } on FormatException {
    return const RedditPost();
  }
  if (j is! List) return const RedditPost();
  for (final i in j) {
    if (i is! Map) continue;
    final type = '${i['dataType'] ?? 'post'}';
    if (type != 'post') continue;
    final sub = '${i['parsedCommunityName'] ?? i['communityName'] ?? ''}'.replaceFirst(RegExp(r'^r/'), '');
    final videos = _strs(i['videoUrls']);
    return RedditPost(
      author: '${i['username'] ?? ''}',
      subreddit: sub,
      title: '${i['title'] ?? ''}'.trim(),
      body: '${i['body'] ?? ''}'.trim(),
      images: _strs(i['imageUrls']).take(maxRedditImages).toList(),
      videoUrl: videos.isEmpty ? '' : videos.first,
    );
  }
  return const RedditPost();
}

/// The post id of a full Reddit link (`/comments/<id>/...`) or a redd.it short link; null for `/s/` share links and anything else.
String? redditPostId(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !isRedditHost(u.host)) return null;
  final seg = u.pathSegments.where((e) => e.isNotEmpty).toList();
  final String? id;
  if (u.host.toLowerCase() == 'redd.it') {
    id = seg.isEmpty ? null : seg.first;
  } else {
    final i = seg.indexOf('comments');
    id = i >= 0 && i + 1 < seg.length ? seg[i + 1] : null;
  }
  return id != null && RegExp(r'^[a-z0-9]{4,10}$').hasMatch(id) ? id : null;
}

Uri arcticShiftPostUri(String id) => Uri.https('arctic-shift.photon-reddit.com', '/api/posts/ids', {'ids': 't3_$id'});

String _unescape(String s) => s.replaceAll('&amp;', '&');

/// The post from Arctic Shift's `/api/posts/ids` answer. Removed or deleted bodies count as empty.
RedditPost parseArcticShiftPost(String body) {
  Object? j;
  try {
    j = jsonDecode(body);
  } on FormatException {
    return const RedditPost();
  }
  final data = j is Map ? j['data'] : null;
  if (data is! List || data.isEmpty || data.first is! Map) return const RedditPost();
  final i = data.first as Map;
  String text(Object? v) {
    final t = '${v ?? ''}'.trim();
    return t == '[removed]' || t == '[deleted]' ? '' : t;
  }

  final images = <String>[];
  final meta = i['media_metadata'];
  if (meta is Map) {
    for (final m in meta.values) {
      final src = m is Map && m['s'] is Map ? (m['s'] as Map)['u'] : null;
      if (src is String && isRedditMedia(_unescape(src))) images.add(_unescape(src));
    }
  }
  final url = '${i['url'] ?? ''}';
  if (images.isEmpty && isRedditMedia(url) && RegExp(r'\.(jpe?g|png|webp)(\?|$)', caseSensitive: false).hasMatch(url)) images.add(url);
  var video = '';
  final media = i['media'];
  final rv = media is Map ? media['reddit_video'] : null;
  if (rv is Map && '${rv['fallback_url'] ?? ''}'.isNotEmpty && isRedditMedia(_unescape('${rv['fallback_url']}'))) {
    video = _unescape('${rv['fallback_url']}');
  }
  return RedditPost(
    author: text(i['author']),
    subreddit: text(i['subreddit']),
    title: text(i['title']),
    body: text(i['selftext']),
    images: images.take(maxRedditImages).toList(),
    videoUrl: video,
  );
}
