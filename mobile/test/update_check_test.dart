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
}
