import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reelbrain/core/models.dart';
import 'package:reelbrain/data/export.dart';
import 'package:reelbrain/data/library_db.dart';
import 'package:reelbrain/native/counter_bridge.dart';
import 'package:reelbrain/pipeline/background.dart';
import 'package:reelbrain/pipeline/gemini.dart';
import 'package:reelbrain/pipeline/runner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeBridge implements CounterBridge {
  final List<PendingItem> items;
  final Map<int, String> statuses = {};
  IgFetch Function(String url) fetch;
  FakeBridge(this.items, {IgFetch Function(String)? fetch}) : fetch = fetch ?? ((_) => const IgFetch());

  // The runner never touches the counter methods.
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(i.memberName.toString());

  @override
  Future<List<PendingItem>> pendingItems({String? status}) async =>
      items.where((i) => !statuses.containsKey(i.id)).toList();
  final Map<int, String> titles = {};
  @override
  Future<void> setPendingStatus(int id, String status, {String title = ''}) async {
    statuses[id] = status;
    titles[id] = title;
  }
  @override
  Future<IgFetch> fetchInstagram(String url) async => fetch(url);
  @override
  Future<List<List<int>>> videoFrames(String path, {int count = 6}) async => [
        [1, 2, 3],
      ];
  @override
  Future<void> saveDownload(String name, String text) async {}
  final notified = <(String, String)>[];
  @override
  Future<void> notifyNotes(String title, String text) async => notified.add((title, text));
}

const _note = {
  'title': 'Rice',
  'overview': ['Rinse rice twice', 'Use 1:1.5 water'],
  'summary': 'How to cook rice.',
  'keyPoints': ['Rinse'],
  'mentions': ['Rice cooker'],
  'tags': ['food'],
};

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
          {List<String> gemini = const ['KEY'], String? apify, String? openai}) =>
      Runner(
        bridge: b,
        library: db,
        client: MockClient((r) {
          requests.add(r);
          return handler(r);
        }),
        keys: () async => AnalysisKeys(gemini: gemini, openai: openai),
        apifyKey: () async => apify,
        makeGemini: (k) => Gemini(
            MockClient((r) {
              requests.add(r);
              return handler(r);
            }),
            k,
            pollEvery: Duration.zero),
        tempDir: tmp,
        rateWait: Duration.zero,
      );

  const yt = PendingItem(id: 1, url: 'https://www.youtube.com/shorts/abcdefg', app: 'youtube', createdAt: 5);
  const ig = PendingItem(id: 2, url: 'https://www.instagram.com/reel/Cuy8bLvo1Xa/', app: 'instagram', createdAt: 6);

  bool isGenerate(http.Request r) => r.url.path.contains(':generateContent');
  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  test('T-PIPE-01 Shorts URL goes to Gemini as fileData', () async {
    final b = FakeBridge([yt]);
    final run = runner(b, (r) async => http.Response(_gemOk(), 200));
    expect(await run.processQueue(), 1);
    expect(run.finishedTitles, ['Rice']); // for the "note ready" notification
    final part = body(requests.where(isGenerate).single)['contents'][0]['parts'][0];
    expect(part['fileData']['fileUri'], 'https://www.youtube.com/watch?v=abcdefg');
    expect(part['videoMetadata']['fps'], 0.5); // token saver: half Gemini's default frame rate
    expect(body(requests.where(isGenerate).single)['generationConfig']['thinkingConfig']['thinkingLevel'], 'minimal');
    expect(requests.where(isGenerate).single.headers['x-goog-api-key'], 'KEY');
    expect(b.statuses[1], 'done');
    expect((await db.reels()).single.title, 'Rice');
    expect(b.titles[1], 'Rice'); // for the digest
    final saved = (await db.reels()).single;
    expect(saved.overview, ['Rinse rice twice', 'Use 1:1.5 water']);
    expect(saved.mentions, ['Rice cooker']);
    expect(body(requests.where(isGenerate).single)['generationConfig']['responseSchema']['required'], contains('overview'));
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
    expect((await db.reels()).single.step, 7); // Apify is step 7 since the embed player became step 2
  });

  test('T-PIPE-06 429 keeps the item queued; 400 tries next level then next model', () async {
    final b = FakeBridge([yt]);
    final r429 = runner(b, (r) async => http.Response('busy', 429));
    await r429.processQueue();
    expect(b.statuses, isEmpty);
    expect(r429.lastProblem, contains('429'));

    final b2 = FakeBridge([const PendingItem(id: 3, url: '', app: 'instagram', caption: 'c')]);
    var n = 0;
    await runner(b2, (r) async => ++n < 3 ? http.Response('{"error":"bad thinking level"}', 400) : http.Response(_gemOk(), 200))
        .processQueue();
    final models = requests.where(isGenerate).map((r) => r.url.pathSegments.last.split(':').first).toList();
    expect(models.last, Gemini.models[1]); // after Flash-Lite refuses twice, 3.6 Flash
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
    expect(await runner(b, (r) async => http.Response(_gemOk(), 200), gemini: []).processQueue(), 0);
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
    final r = runner(b, (r) async => http.Response(_gemOk(), 200));
    await r.processQueue();
    expect(b.statuses, isEmpty);
    expect(r.lastProblem, contains('Instagram is limiting'));

    // A post walled on every step (a private account's, say) is not a rate limit, and the library says so.
    final walled = runner(FakeBridge([ig], fetch: (_) => throw RateLimited('every step hit a login wall; retrying in 3 min')),
        (r) async => http.Response(_gemOk(), 200));
    await walled.processQueue();
    expect(walled.lastProblem, contains('wants a login'));
  });

  test('T-PIPE-11 Gemini keys take turns, one reel each; a 429 moves the reel to the next key', () async {
    final b = FakeBridge([yt, const PendingItem(id: 3, url: 'https://www.youtube.com/shorts/zzzzzzz', app: 'youtube', createdAt: 7)]);
    await runner(b, (r) async => http.Response(_gemOk(), 200), gemini: ['K1', 'K2']).processQueue();
    expect(requests.where(isGenerate).map((r) => r.headers['x-goog-api-key']), ['K1', 'K2']);

    requests.clear();
    final b2 = FakeBridge([const PendingItem(id: 4, url: 'https://www.youtube.com/shorts/yyyyyyy', app: 'youtube', createdAt: 8)]);
    await runner(b2, (r) async => r.headers['x-goog-api-key'] == 'K1' ? http.Response('busy', 429) : http.Response(_gemOk(), 200),
        gemini: ['K1', 'K2']).processQueue();
    expect(requests.where(isGenerate).map((r) => r.headers['x-goog-api-key']), ['K1', 'K2']);
    expect(b2.statuses[4], 'done');
  });

  test('a 429 on every key waits once and tries again in the same run', () async {
    var calls = 0;
    final b = FakeBridge([yt]);
    await runner(b, (r) async => ++calls == 1 ? http.Response('{"error":{"status":"RESOURCE_EXHAUSTED"}}', 429) : http.Response(_gemOk(), 200))
        .processQueue();
    expect(b.statuses[1], 'done');
  });

  test('reels added while a run is busy are picked up in the same run', () async {
    final b = FakeBridge([yt]);
    var added = false;
    await runner(b, (r) async {
      if (!added) {
        added = true;
        b.items.add(const PendingItem(id: 9, url: 'https://www.youtube.com/shorts/lateone1', app: 'youtube', createdAt: 9));
      }
      return http.Response(_gemOk(), 200);
    }).processQueue();
    expect(b.statuses.keys, containsAll([1, 9]));
  });

  test('transcript and on-screen text are saved and searchable', () async {
    final j = jsonDecode(_gemOk()) as Map;
    final note = {..._note, 'transcript': 'hello zebra world', 'onScreenText': 'Step one'};
    final ok = jsonEncode({'candidates': [{'content': {'parts': [{'text': jsonEncode(note)}]}}]});
    j.clear();
    final b = FakeBridge([yt]);
    await runner(b, (r) async => http.Response(ok, 200)).processQueue();
    final r = (await db.reels(query: 'zebra')).single;
    expect(r.transcript, 'hello zebra world');
    expect(r.onScreenText, 'Step one');
    expect(r.toMarkdown(), contains('## Transcript'));
  });

  test('with several Gemini keys, reels are analysed at the same time, each on its own key', () async {
    var live = 0, peak = 0;
    final keysSeen = <String?>[];
    final b = FakeBridge([
      yt,
      const PendingItem(id: 3, url: 'https://www.youtube.com/shorts/zzzzzzz', app: 'youtube', createdAt: 7),
      const PendingItem(id: 4, url: 'https://www.youtube.com/shorts/yyyyyyy', app: 'youtube', createdAt: 8),
    ]);
    await runner(b, (r) async {
      if (!isGenerate(r)) return http.Response('', 404);
      keysSeen.add(r.headers['x-goog-api-key']);
      peak = ++live > peak ? live : peak;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      live--;
      return http.Response(_gemOk(), 200);
    }, gemini: ['K1', 'K2', 'K3']).processQueue();
    expect(peak, 3);
    expect(keysSeen.toSet(), {'K1', 'K2', 'K3'});
    expect(b.statuses.keys, containsAll([1, 3, 4]));
    expect((await db.reels()).map((r) => r.url).toSet().length, 3);
  });

  test('a reel stopped before it starts is not analysed; each reel has its own progress', () async {
    final b = FakeBridge([
      yt,
      const PendingItem(id: 3, url: 'https://www.youtube.com/shorts/zzzzzzz', app: 'youtube', createdAt: 7),
    ]);
    late Runner r;
    r = runner(b, (req) async {
      if (!isGenerate(req)) return http.Response('', 404);
      await r.cancel(3); // stopped while the first reel is being analysed
      return http.Response(_gemOk(), 200);
    });
    final seen = <String>{};
    r.jobs.addListener(() => seen.addAll(r.jobs.value.map((j) => '${j.id}:${j.stage}')));
    await r.processQueue();
    expect(b.statuses[1], 'done');
    expect(b.statuses[3], 'cancelled');
    expect(await db.has('https://www.youtube.com/shorts/zzzzzzz'), isFalse);
    expect(seen.any((x) => x.startsWith('1:Analysing')), isTrue);
  });

  test('errors are explained in words, with the real cause', () {
    expect(
      describeError(GeminiException(GeminiFailure.retryLater, 'HTTP 429: {"error":{"code":429,"message":"Quota exceeded for this key.","status":"RESOURCE_EXHAUSTED"}}')),
      'The AI is busy or rate-limited: Quota exceeded for this key.',
    );
    expect(describeError(const SocketException('Failed host lookup')), startsWith('No internet connection'));
    expect(describeError(TimeoutException('x')), contains('timed out'));
  });

  test('a reel nothing can be fetched for fails with a reason shown in the list', () async {
    final b = FakeBridge([ig]);
    final r = runner(b, (_) async => http.Response(_gemOk(), 200));
    await r.processQueue();
    expect(b.statuses[2], 'failed');
    expect(r.jobs.value.single.state, JobState.failed);
    expect(r.jobs.value.single.stage, contains('no video, picture, caption or author'));
  });

  test('T-PIPE-12 no Gemini key: OpenAI gets frames from the video', () async {
    final f = File('${tmp.path}/v.mp4')..writeAsBytesSync([0]);
    final b = FakeBridge([ig], fetch: (_) => IgFetch(step: 1, videoPath: f.path));
    await runner(b, (r) async => http.Response(jsonEncode({'choices': [{'message': {'content': '```json\n${jsonEncode(_note)}\n```'}}]}), 200),
        gemini: [], openai: 'OK').processQueue();
    final r = requests.single;
    expect(r.url.host, 'api.openai.com');
    expect(r.headers['Authorization'], 'Bearer OK');
    expect(jsonEncode(body(r)), contains('image_url'));
    expect(b.statuses[2], 'done');
    expect((await db.reels()).single.title, 'Rice');
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

  test('T-EXP-01 export, wipe, import (notes and chats); import twice adds nothing', () async {
    await db.saveReel(const Reel(url: 'u1', app: 'youtube', title: 'A', summary: 's', tags: ['x'], savedAt: 1));
    await db.saveReel(const Reel(url: 'u2', app: 'instagram', title: 'B', summary: 's', savedAt: 2));
    final chat = await db.saveChat(null, ['q?', 'a.'], 5);
    final json = exportJson(await db.reels(), await db.chats());
    await db.delete('u1');
    await db.delete('u2');
    await db.deleteChat(chat);
    expect(await importJson(db, json), (2, 1));
    expect(await importJson(db, json), (0, 0));
    final (_, title, at, turns) = (await db.chats()).single;
    expect((title, at), ('q?', 5));
    expect(turns, ['q?', 'a.']);
    expect(await importJson(db, '{"version":1,"reels":[]}'), (0, 0), reason: 'v1 files have no chats');
    final r = await db.reels();
    expect(r.map((e) => e.url), ['u2', 'u1']);
    expect(r.last.tags, ['x']);
    expect(markdownName(r.first), endsWith('-b.md'));
  });

  test('T-LIB-01 unseen notes stay; seen notes older than 3 days move to the archive', () async {
    const day = 24 * 3600 * 1000;
    final now = 10 * day;
    for (final (url, saved) in [('a', now - 4 * day), ('b', now - 4 * day), ('c', now - day)]) {
      await db.saveReel(Reel(url: url, app: 'youtube', title: url, summary: '', savedAt: saved));
    }
    await db.markSeen('a', now);
    await db.markSeen('c', now);
    expect(await db.archiveOld(now), 1);
    expect((await db.reels(archived: false)).map((r) => r.url), ['c', 'b']); // b is unseen: it waits for you
    expect((await db.reels(archived: true)).single.url, 'a');
    expect((await db.reels()).length, 3); // chat and export still see everything
    expect((await db.reels(archived: false)).firstWhere((r) => r.url == 'b').seenAt, 0);
    await db.setArchived('a', false);
    expect((await db.reels(archived: true)), isEmpty);
  });

  test('T-PIPE-13 a retried note goes back through the queue instead of being skipped as saved', () async {
    final b = FakeBridge([ig], fetch: (_) => const IgFetch(step: 1, author: 'chef'));
    final run = runner(b, (r) async => http.Response(_gemOk(), 200));
    await run.processQueue();
    expect(b.statuses[2], 'text-only');
    // What AppServices.retry does: re-queue the row, drop the note.
    b.statuses.remove(2);
    await db.delete(ig.url);
    b.fetch = (_) => IgFetch(step: 2, videoPath: (File('${tmp.path}/v.mp4')..writeAsBytesSync([0])).path);
    await run.processQueue();
    expect(b.statuses[2], 'done');
    expect((await db.reels()).single.step, 2);
  });

  test('T-PIPE-14 a shared photo goes to Gemini as an image and is saved as a note', () async {
    final f = File('${tmp.path}/p.jpg')..writeAsBytesSync([0xFF, 0xD8, 1, 2]);
    final b = FakeBridge([PendingItem(id: 9, url: 'photo:${f.path}', app: 'photo', caption: 'from my gallery', createdAt: 5)]);
    await runner(b, (r) async => http.Response(_gemOk(), 200)).processQueue();
    final parts = body(requests.single)['contents'][0]['parts'] as List;
    expect(parts.first['inlineData']['mimeType'], 'image/jpeg');
    expect(jsonEncode(parts), contains('not a video'));
    expect(b.statuses[9], 'done');
    final r = (await db.reels()).single;
    expect((r.app, r.url, r.title), ('photo', 'photo:${f.path}', 'Rice'));
  });

  test('T-PIPE-15 an Instagram carousel post sends every picture in one request', () async {
    final b = FakeBridge([const PendingItem(id: 10, url: 'https://www.instagram.com/p/Cpost123/', app: 'instagram', createdAt: 5)],
        fetch: (_) => const IgFetch(step: 1, author: 'a', caption: 'tips', images: ['https://cdn/1.jpg', 'https://cdn/2.jpg', 'https://cdn/3.jpg']));
    await runner(b, (r) async => r.url.host == 'cdn' ? http.Response.bytes([1, 2, 3], 200) : http.Response(_gemOk(), 200)).processQueue();
    final gen = requests.where(isGenerate).single;
    final parts = body(gen)['contents'][0]['parts'] as List;
    expect(parts.where((p) => p['inlineData'] != null).length, 3);
    expect(jsonEncode(parts), contains('3 images of one post'));
    expect(b.statuses[10], 'done');
  });

  test('T-LIB-02 chats are saved, updated, listed newest first and deleted', () async {
    final a = await db.saveChat(null, ['q1', 'a1'], 1);
    final b = await db.saveChat(null, ['q2', 'a2'], 2);
    await db.saveChat(a, ['q1', 'a1', 'q3', 'a3'], 3);
    final all = await db.chats();
    expect(all.map((c) => c.$1), [a, b]);
    expect(all.first.$4, ['q1', 'a1', 'q3', 'a3']);
    expect(all.first.$2, 'q1');
    await db.deleteChat(b);
    expect((await db.chats()).length, 1);
  });

  test('T-LIB-03 search finds words only in the overview or mentions', () async {
    await db.saveReel(const Reel(url: 'x', app: 'youtube', title: 'T', summary: 's', savedAt: 1, overview: ['Use a pressure cooker'], mentions: ['Notion']));
    expect((await db.reels(query: 'pressure')).single.url, 'x');
    expect((await db.reels(query: 'notion')).single.url, 'x');
  });

  test('search matches tags and summary', () async {
    await db.saveReel(const Reel(url: 'u1', app: 'youtube', title: 'Rice', summary: 'boil', tags: ['food'], savedAt: 1));
    await db.saveReel(const Reel(url: 'u2', app: 'youtube', title: 'Squats', summary: 'legs', savedAt: 2));
    expect((await db.reels(query: 'food')).single.url, 'u1');
    expect((await db.reels(query: 'LEGS')).single.url, 'u2');
  });

  test('T-BG-01 the background task analyses the queue and posts one "note ready"', () async {
    final yt2 = PendingItem(id: 3, url: 'https://www.youtube.com/shorts/hijklmn', app: 'youtube', createdAt: 7);
    final b = FakeBridge([yt, yt2]);
    await analyseAndNotify(runner(b, (r) async => http.Response(_gemOk(), 200)), b);
    expect(b.statuses, {1: 'done', 3: 'done'});
    expect(b.notified, [('2 notes ready', 'Rice · Rice')]);

    // Nothing queued: no notification.
    final idle = FakeBridge([]);
    await analyseAndNotify(runner(idle, (r) async => http.Response(_gemOk(), 200)), idle);
    expect(idle.notified, isEmpty);
  });

  test('T-PIPE-16 a link shared again is not analysed twice; its note comes back to the top, unread', () async {
    await db.saveReel(const Reel(url: 'https://www.youtube.com/shorts/abcdefg', app: 'youtube', title: 'Rice', summary: '', savedAt: 1, seenAt: 5));
    await db.setArchived('https://www.youtube.com/shorts/abcdefg', true);
    await db.saveReel(const Reel(url: 'u2', app: 'youtube', title: 'Newer', summary: '', savedAt: 2));
    final b = FakeBridge([yt]);
    await runner(b, (r) async => http.Response(_gemOk(), 200)).processQueue();
    expect(requests, isEmpty); // no tokens spent
    expect(b.statuses[1], 'done');
    final top = (await db.reels(archived: false)).first;
    expect((top.title, top.seenAt, top.archived), ('Rice', 0, false));
  });

  test('T-LIB-04 Undo helpers: mark unread, restore a deleted chat with its id', () async {
    await db.saveReel(const Reel(url: 'u', app: 'youtube', title: 'A', summary: '', savedAt: 1));
    await db.markSeen('u', 9);
    await db.markUnseen('u');
    expect((await db.reels()).single.seenAt, 0);
    final id = await db.saveChat(null, ['q', 'a'], 7);
    final chat = (await db.chats()).single;
    await db.deleteChat(id);
    await db.restoreChat(chat);
    final back = (await db.chats()).single;
    expect((back.$1, back.$2, back.$3), (chat.$1, chat.$2, chat.$3));
    expect(back.$4, chat.$4);
  });
}
