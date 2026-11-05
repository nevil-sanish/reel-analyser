import 'dart:convert';

import 'package:http/http.dart' as http;

/// GH-RELEASE-LATEST. Every release is a pre-release, which `/releases/latest` leaves out, so this reads
/// the newest entry of `/releases`. Returns (tag, apk url) when it's newer than [current]; null otherwise,
/// and on any failure (offline, a 403 rate limit, an odd body), so the app stays silent.
Future<(String, String)?> newerRelease(http.Client client, String current) async {
  try {
    final r = await client.get(Uri.parse('https://api.github.com/repos/nevil-sanish/reel-brain/releases?per_page=1'),
        headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final rel = (jsonDecode(r.body) as List).first as Map;
    final tag = rel['tag_name'] as String;
    final apk = [for (final a in rel['assets'] as List) if ('${a['name']}'.endsWith('.apk')) '${a['browser_download_url']}'];
    if (apk.isEmpty || !isNewer(tag, current)) return null;
    return (tag, apk.first);
  } catch (_) {
    return null;
  }
}

/// `v0.10.0` > `0.9.3`: compared number by number.
bool isNewer(String tag, String current) {
  List<int> parts(String v) => [for (final p in v.replaceFirst('v', '').split('.')) int.tryParse(p) ?? 0];
  final a = parts(tag), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
