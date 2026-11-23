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

/// One run of any Apify actor for a single input, returning the dataset body (JSON text). The key goes in a header, never the URL.
/// Used for LinkedIn and Reddit posts; null when the actor answered with nothing usable.
Future<String?> apifyActorRun(http.Client client, String key, String actor, Map<String, Object?> input) async {
  final r = await client
      .post(
        Uri.parse('https://api.apify.com/v2/acts/$actor/run-sync-get-dataset-items?timeout=120'),
        headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
        body: jsonEncode(input),
      )
      .timeout(const Duration(seconds: 150));
  if (r.statusCode == 401 || r.statusCode == 403) throw ApifyException('Your Apify key was rejected. Check it in Settings.');
  if (r.statusCode == 402) throw ApifyException('Your Apify account is out of credit.');
  if (r.statusCode != 200 && r.statusCode != 201) throw ApifyException('Apify could not run this (HTTP ${r.statusCode}).');
  return utf8.decode(r.bodyBytes);
}
