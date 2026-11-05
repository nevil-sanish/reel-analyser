import 'dart:convert';

import 'package:http/http.dart' as http;

class ApifyResult {
  final String videoUrl;
  final String thumbnailUrl;
  final String caption;
  final String author;
  const ApifyResult({this.videoUrl = '', this.thumbnailUrl = '', this.caption = '', this.author = ''});
}

class ApifyException implements Exception {
  final String message;
  ApifyException(this.message);
  @override
  String toString() => message;
}

/// APIFY-RUN: cascade step 6, only when the user saved an Apify key. The key goes in a header, never the URL.
Future<ApifyResult?> apifyFetch(http.Client client, String key, String code) async {
  final r = await client
      .post(
        Uri.parse('https://api.apify.com/v2/acts/apify~instagram-scraper/run-sync-get-dataset-items?timeout=120'),
        headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'directUrls': ['https://www.instagram.com/p/$code/'],
          'resultsType': 'posts',
          'resultsLimit': 1,
        }),
      )
      .timeout(const Duration(seconds: 150));
  if (r.statusCode == 401 || r.statusCode == 403) throw ApifyException('Your Apify key was rejected. Check it in Settings.');
  if (r.statusCode == 402) throw ApifyException('Your Apify account is out of credit.');
  if (r.statusCode != 200 && r.statusCode != 201) return null;
  final items = jsonDecode(utf8.decode(r.bodyBytes));
  if (items is! List || items.isEmpty) return null;
  final i = items.first as Map;
  var video = '${i['videoUrl'] ?? ''}';
  if (video.isEmpty && i['childPosts'] is List) {
    video = (i['childPosts'] as List).map((c) => '${c['videoUrl'] ?? ''}').firstWhere((v) => v.isNotEmpty, orElse: () => '');
  }
  return ApifyResult(
    videoUrl: video,
    thumbnailUrl: '${i['displayUrl'] ?? ''}',
    caption: '${i['caption'] ?? ''}',
    author: '${i['ownerUsername'] ?? ''}',
  );
}
