import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reelbrain/data/update_check.dart';

void main() {
  test('a fourth version number counts: 0.9.7.1 is newer than 0.9.7', () {
    expect(isNewer('v0.9.7.1', '0.9.7'), isTrue);
    expect(isNewer('v0.9.7', '0.9.7.1'), isFalse);
    expect(isNewer('v0.9.7.1', '0.9.7.1'), isFalse);
  });

  http.Client gh(int status, String tag) => MockClient((_) async => http.Response(
      jsonEncode([
        {
          'tag_name': tag,
          'assets': [
            {'name': 'SHA256SUMS', 'browser_download_url': 'https://x/sums'},
            {'name': 'reel-bot-$tag.apk', 'browser_download_url': 'https://x/$tag.apk'},
          ],
        }
      ]),
      status));

  test('T-REL-01 newer tag gives the apk; same, older or 403 gives nothing', () async {
    expect(await newerRelease(gh(200, 'v0.10.0'), '0.9.3', semi: false), ('v0.10.0', 'https://x/v0.10.0.apk'));
    expect(await newerRelease(gh(200, 'v0.9.3'), '0.9.3', semi: false), isNull);
    expect(await newerRelease(gh(200, 'v0.9.2'), '0.9.3', semi: false), isNull);
    expect(await newerRelease(gh(403, 'v1.0.0'), '0.9.3', semi: false), isNull);
    expect(await newerRelease(MockClient((_) async => http.Response('nope', 200)), '0.9.3', semi: false), isNull);
  });

  // The API is rate-limited (403); the website's /releases/latest redirect still names the newest tag.
  http.Client limited(String? tag) => MockClient((req) async => req.url.host == 'api.github.com'
      ? http.Response('{"message":"API rate limit exceeded"}', 403)
      : http.Response('', 302,
          headers: {if (tag != null) 'location': 'https://github.com/nevil-sanish/reel-analyser/releases/tag/$tag'}));

  test('rate-limited API falls back to the latest-release redirect', () async {
    final u = await latestUpdate(limited('v1.2.1.1'), '1.2.1.0', semi: true);
    expect(u?.tag, 'v1.2.1.1');
    expect(u?.apkUrl, 'https://github.com/nevil-sanish/reel-analyser/releases/download/v1.2.1.1/reel-analyser-v1.2.1.1-semi.apk');
    expect(u?.sumsUrl, 'https://github.com/nevil-sanish/reel-analyser/releases/download/v1.2.1.1/SHA256SUMS');
    expect(await latestUpdate(limited('v1.2.1.1'), '1.2.1.1', semi: false), isNull);
    expect(await latestUpdate(limited(null), '1.2.1.0', semi: false), isNull);
  });
}
