import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reelbrain/core/models.dart';
import 'package:reelbrain/data/export.dart';
import 'package:reelbrain/data/library_db.dart';
import 'package:reelbrain/native/counter_bridge.dart';
import 'package:reelbrain/pipeline/gemini.dart';
import 'package:reelbrain/pipeline/runner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeBridge implements CounterBridge {
  final List<PendingItem> items;
  final Map<int, String> statuses = {};
  IgFetch Function(String url) fetch;
  FakeBridge(this.items, {IgFetch Function(String)? fetch}) : fetch = fetch ?? ((_) => const IgFetch());

  @override
  Future<List<PendingItem>> pendingItems({String? status}) async =>
      items.where((i) => !statuses.containsKey(i.id)).toList();
  @override
  Future<void> setPendingStatus(int id, String status) async => statuses[id] = status;
  @override
  Future<IgFetch> fetchInstagram(String url) async => fetch(url);
  @override
  Future<void> saveDownload(String name, String text) async {}
}

const _note = {'title': 'Rice', 'summary': 'How to cook rice.', 'keyPoints': ['Rinse'], 'tags': ['food']};

String _gemOk() => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'thinking', 'thought': true},
              {'text': jsonEncode(_note)},
            ],
          },
        },
      ],
    });

void main() {
  sqfliteFfiInit();
  late LibraryDb db;
  late Directory tmp;
  final requests = <http.Request>[];

  setUp(() async {
    db = await LibraryDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    tmp = await Directory.systemTemp.createTemp('reelbot');
    requests.clear();
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Runner runner(FakeBridge b, Future<http.Response> Function(http.Request) handler,
          {String? gemini = 'KEY', String? apify}) =>
      Runner(
        bridge: b,
        library: db,
        client: MockClient((r) {
          requests.add(r);
          return handler(r);
        }),
        geminiKey: () async => gemini,
        apifyKey: () async => apify,
        makeGemini: (k) => Gemini(
            MockClient((r) {
              requests.add(r);
              return handler(r);
            }),
            k,
            pollEvery: Duration.zero),
        tempDir: tmp,
      );

  const yt = PendingItem(id: 1, url: 'https://www.youtube.com/shorts/abcdefg', app: 'youtube', createdAt: 5);
  const ig = PendingItem(id: 2, url: 'https://www.instagram.com/reel/Cuy8bLvo1Xa/', app: 'instagram', createdAt: 6);

  bool isGenerate(http.Request r) => r.url.path.contains(':generateContent');
  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  test('T-PIPE-01 Shorts URL goes to Gemini as fileData', () async {
    final b = FakeBridge([yt]);
    await runner(b, (r) async => http.Response(_gemOk(), 200)).processQueue();
    final part = body(requests.single)['contents'][0]['parts'][0];
    expect(part['fileData']['fileUri'], yt.url);
    expect(requests.single.headers['x-goog-api-key'], 'KEY');
    expect(b.statuses[1], 'done');
    expect((await db.reels()).single.title, 'Rice');
  });

  test('T-PIPE-02 rejected YouTube URL falls back to oEmbed', () async {
    final b = FakeBridge([yt]);
    await runner(b, (r) async {
      if (r.url.host == 'www.youtube.com') {
        return http.Response(jsonEncode({'title': 'T', 'author_name': 'chan', 'thumbnail_url': ''}), 200);
      }
      final fileUri = body(r)['contents'][0]['parts'][0]['fileData'];
      return fileUri != null ? http.Response('{"error":{"message":"private video"}}', 400) : http.Response(_gemOk(), 200);
    }).processQueue();
    expect(b.statuses[1], 'caption+thumbnail');
    expect((await db.reels()).single.author, 'chan');
  });

  test('T-PIPE-03 small Instagram video goes inline and is deleted', () async {
    final f = File('${tmp.path}/v.mp4')..writeAsBytesSync([1, 2, 3]);
    final b = FakeBridge([ig], fetch: (_) => IgFetch(step: 1, author: 'chef', caption: 'cap', videoPath: f.path));
    await runner(b, (r) async => http.Response(_gemOk(), 200)).processQueue();
    final parts = body(requests.single)['contents'][0]['parts'] as List;
    expect(parts[0]['inlineData']['mimeType'], 'video/mp4');
    expect(b.statuses[2], 'done');
    expect((await db.reels()).single.step, 1);
    expect(f.existsSync(), isFalse);
  });

  test('T-PIPE-04 caption + thumbnail only', () async {
    final b = FakeBridge([ig], fetch: (_) => const IgFetch(step: 5, caption: 'cap', thumbnailUrl: 'https://cdn/t.jpg'));
    await runner(b, (r) async => isGenerate(r) ? http.Response(_gemOk(), 200) : http.Response.bytes([9, 9], 200))
        .processQueue();
    expect(b.statuses[2], 'caption+thumbnail');
    final parts = body(requests.firstWhere(isGenerate))['contents'][0]['parts'] as List;
    expect(parts[0]['inlineData']['mimeType'], 'image/jpeg');
  });

  test('T-PIPE-05 Apify key goes in the header, never the URL', () async {
    final b = FakeBridge([ig], fetch: (_) => const IgFetch(step: 5, caption: 'cap'));
    await runner(b, (r) async {
      if (r.url.host == 'api.apify.com') return http.Response(jsonEncode([{'videoUrl': 'https://cdn/v.mp4'}]), 201);
      if (r.url.host == 'cdn') return http.Response.bytes([1, 2], 200);
      return http.Response(_gemOk(), 200);
    }, apify: 'APIFYSECRET')
        .processQueue();
    final a = requests.firstWhere((r) => r.url.host == 'api.apify.com');
    expect(a.headers['Authorization'], 'Bearer APIFYSECRET');
    expect(a.url.toString(), isNot(contains('APIFYSECRET')));
    expect(b.statuses[2], 'done');
    expect((await db.reels()).single.step, 6);
  });

  test('T-PIPE-06 429 keeps the item queued; 400 tries next level then next model', () async {
    final b = FakeBridge([yt]);
    await runner(b, (r) async => http.Response('busy', 429)).processQueue();
    expect(b.statuses, isEmpty);

    final b2 = FakeBridge([const PendingItem(id: 3, url: '', app: 'instagram', caption: 'c')]);
    var n = 0;
    await runner(b2, (r) async => ++n < 3 ? http.Response('{"error":"bad thinking level"}', 400) : http.Response(_gemOk(), 200))
        .processQueue();
    final models = requests.where(isGenerate).map((r) => r.url.pathSegments.last.split(':').first).toList();
    expect(models.last, Gemini.models[1]);
    expect(b2.statuses[3], 'text-only');
  });

  test('T-PIPE-07 large video uses the Files API and deletes the file', () async {
    final f = File('${tmp.path}/big.mp4')..writeAsBytesSync(List.filled(Gemini.inlineLimit + 1, 0));
    final b = FakeBridge([ig], fetch: (_) => IgFetch(step: 2, videoPath: f.path));
    var polls = 0;
    await runner(b, (r) async {
      if (r.url.path == '/upload/v1beta/files') return http.Response('{}', 200, headers: {'x-goog-upload-url': 'https://up/1'});
      if (r.url.host == 'up') return http.Response(jsonEncode({'file': {'name': 'files/x', 'uri': 'U', 'state': 'PROCESSING'}}), 200);
      if (r.method == 'GET') return http.Response(jsonEncode({'name': 'files/x', 'uri': 'U', 'state': ++polls > 1 ? 'ACTIVE' : 'PROCESSING'}), 200);
      if (r.method == 'DELETE') return http.Response('{}', 200);
      return http.Response(_gemOk(), 200);
    }).processQueue();
    expect(body(requests.firstWhere(isGenerate))['contents'][0]['parts'][0]['fileData']['fileUri'], 'U');
    expect(requests.any((r) => r.method == 'DELETE' && r.url.path == '/v1beta/files/x'), isTrue);
    expect(b.statuses[2], 'done');
  });

  test('T-PIPE-08 no Gemini key leaves everything queued', () async {
    final b = FakeBridge([yt, ig]);
    expect(await runner(b, (r) async => http.Response(_gemOk(), 200), gemini: null).processQueue(), 0);
    expect(b.statuses, isEmpty);
    expect(requests, isEmpty);
  });

  test('T-PIPE-09 nothing found and nothing captured → failed', () async {
    final b = FakeBridge([ig]);
    await runner(b, (r) async => http.Response(_gemOk(), 200)).processQueue();
    expect(b.statuses[2], 'failed');
    expect(requests, isEmpty);
  });

  test('Instagram rate limit keeps the item queued', () async {
    final b = FakeBridge([ig], fetch: (_) => throw RateLimited());
    await runner(b, (r) async => http.Response(_gemOk(), 200)).processQueue();
    expect(b.statuses, isEmpty);
  });

  test('T-PIPE-10 the lock lets only one runner through', () async {
    final t = DateTime.now().millisecondsSinceEpoch;
    expect(await db.tryLock(t), isTrue);
    expect(await db.tryLock(t + 1), isFalse);
    final b = FakeBridge([yt]);
    expect(await runner(b, (r) async => http.Response(_gemOk(), 200)).processQueue(), 0);
    expect(b.statuses, isEmpty);
    await db.unlock();
    expect(await db.tryLock(t), isTrue);
    expect(await db.tryLock(t + const Duration(minutes: 6).inMilliseconds), isTrue, reason: 'stale lock expires');
  });

  test('T-EXP-01 export, wipe, import; import twice adds nothing', () async {
    await db.saveReel(const Reel(url: 'u1', app: 'youtube', title: 'A', summary: 's', tags: ['x'], savedAt: 1));
    await db.saveReel(const Reel(url: 'u2', app: 'instagram', title: 'B', summary: 's', savedAt: 2));
    final json = exportJson(await db.reels());
    await db.delete('u1');
    await db.delete('u2');
    expect(await importJson(db, json), 2);
    expect(await importJson(db, json), 0);
    final r = await db.reels();
    expect(r.map((e) => e.url), ['u2', 'u1']);
    expect(r.last.tags, ['x']);
    expect(markdownName(r.first), endsWith('-b.md'));
  });

  test('search matches tags and summary', () async {
    await db.saveReel(const Reel(url: 'u1', app: 'youtube', title: 'Rice', summary: 'boil', tags: ['food'], savedAt: 1));
    await db.saveReel(const Reel(url: 'u2', app: 'youtube', title: 'Squats', summary: 'legs', savedAt: 2));
    expect((await db.reels(query: 'food')).single.url, 'u1');
    expect((await db.reels(query: 'LEGS')).single.url, 'u2');
  });
}
