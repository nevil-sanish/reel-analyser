import 'dart:convert';

import 'package:http/http.dart' as http;

import '../flavor.dart';

/// The newest release and the files an update needs: this build's APK and the checksum list that goes with it.
class UpdateInfo {
  final String tag, apkName, apkUrl;
  final String? sumsUrl;
  const UpdateInfo(this.tag, this.apkName, this.apkUrl, this.sumsUrl);
}

/// GH-RELEASE-LATEST. Every release is a pre-release, which `/releases/latest` leaves out, so this reads
/// the newest entry of `/releases`. Returns (tag, apk url) when it's newer than [current]; null otherwise,
/// and on any failure (offline, a 403 rate limit, an odd body), so the app stays silent.
Future<(String, String)?> newerRelease(http.Client client, String current) async {
  final u = await latestUpdate(client, current);
  return u == null ? null : (u.tag, u.apkUrl);
}

/// Same check, with the checksum file too. A release carries a `-full` and a `-semi` APK; this build takes its own
/// (a release with one unlabelled APK still works).
Future<UpdateInfo?> latestUpdate(http.Client client, String current, {bool semi = kSemiBuild}) async {
  try {
    final r = await client.get(Uri.parse('https://api.github.com/repos/nevil-sanish/reel-analyser/releases?per_page=1'),
        headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final rel = (jsonDecode(r.body) as List).first as Map;
    final tag = rel['tag_name'] as String;
    final assets = [for (final a in rel['assets'] as List) (name: '${a['name']}', url: '${a['browser_download_url']}')];
    final apks = assets.where((a) => a.name.endsWith('.apk')).toList();
    final mine = apks.where((a) => a.name.contains(semi ? '-semi' : '-full')).toList();
    final apk = mine.isNotEmpty ? mine.first : (apks.length == 1 ? apks.first : null);
    if (apk == null || !isNewer(tag, current)) return null;
    final sums = assets.where((a) => a.name == 'SHA256SUMS').toList();
    return UpdateInfo(tag, apk.name, apk.url, sums.isEmpty ? null : sums.first.url);
  } catch (_) {
    return null;
  }
}

/// `v0.10.0` > `0.9.3`: compared number by number.
bool isNewer(String tag, String current) {
  List<int> parts(String v) => [for (final p in v.replaceFirst('v', '').split('.')) int.tryParse(p) ?? 0];
  final a = parts(tag), b = parts(current);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
