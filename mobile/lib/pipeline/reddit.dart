import 'dart:convert';

/// Reddit posts (1.2.4.0, both builds). Reddit shows a post to a logged-out app nowhere: the `.json`, `.rss` and old.reddit pages
/// all answer 403 or 429. So a Reddit post is read only through the user's own Apify key (kept on the phone, sent in a header),
/// and nothing is tried without it.
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
