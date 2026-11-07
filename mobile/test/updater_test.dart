import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reelbrain/data/update_check.dart';
import 'package:reelbrain/data/updater.dart';

void main() {
  final apkBytes = utf8.encode('pretend this is an apk' * 100);
  late Directory dir;
  late String good;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upd');
    good = (await Sha256().hash(apkBytes)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  });
  tearDown(() => dir.delete(recursive: true));

  http.Client host({required String sums}) => MockClient((r) async {
        if (r.url.path.endsWith('SHA256SUMS')) return http.Response(sums, 200);
        return http.Response.bytes(apkBytes, 200);
      });

  const info = UpdateInfo('v9.9.9.9', 'reel-analyser-v9.9.9.9-full.apk',
      'https://github.com/nevil-sanish/reel-analyser/releases/download/v9.9.9.9/reel-analyser-v9.9.9.9-full.apk',
      'https://github.com/nevil-sanish/reel-analyser/releases/download/v9.9.9.9/SHA256SUMS');

  test('a download that matches the checksum is kept and reports progress', () async {
    var last = 0.0;
    final f = await downloadUpdate(host(sums: '$good  reel-analyser-v9.9.9.9-full.apk\nabc  other.apk\n'), info, dir, (p) => last = p);
    expect(await f.readAsBytes(), apkBytes);
    expect(last, 1.0);
  });

  test('a download that does not match is deleted and refused', () async {
    await expectLater(downloadUpdate(host(sums: '${'0' * 64}  reel-analyser-v9.9.9.9-full.apk'), info, dir, (_) {}), throwsA(isA<UpdateException>()));
    expect(File('${dir.path}/reel-analyser.apk').existsSync(), isFalse);
  });

  test('no checksum for the file, or a host that is not GitHub, is refused before any download', () async {
    await expectLater(downloadUpdate(host(sums: 'abc  other.apk'), info, dir, (_) {}), throwsA(isA<UpdateException>()));
    const evil = UpdateInfo('v9', 'a.apk', 'https://evil.example/a.apk', 'https://github.com/x/SHA256SUMS');
    await expectLater(downloadUpdate(host(sums: good), evil, dir, (_) {}), throwsA(isA<UpdateException>()));
    const http1 = UpdateInfo('v9', 'a.apk', 'http://github.com/a.apk', 'https://github.com/x/SHA256SUMS');
    await expectLater(downloadUpdate(host(sums: good), http1, dir, (_) {}), throwsA(isA<UpdateException>()));
  });

  test('each build is offered its own APK (full or semi)', () async {
    final gh = MockClient((_) async => http.Response(
        jsonEncode([
          {
            'tag_name': 'v2.0.0.0',
            'assets': [
              {'name': 'SHA256SUMS', 'browser_download_url': 'https://github.com/s'},
              {'name': 'r-semi.apk', 'browser_download_url': 'https://github.com/p.apk'},
              {'name': 'r-full.apk', 'browser_download_url': 'https://github.com/f.apk'},
            ],
          }
        ]),
        200));
    expect((await latestUpdate(gh, '1.0.0.0', semi: false))!.apkUrl, 'https://github.com/f.apk');
    expect((await latestUpdate(gh, '1.0.0.0', semi: true))!.apkUrl, 'https://github.com/p.apk');
    expect((await latestUpdate(gh, '1.0.0.0'))!.sumsUrl, 'https://github.com/s');
  });
}
