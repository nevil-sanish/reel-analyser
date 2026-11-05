import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../data/library_db.dart';
import '../native/counter_bridge.dart';
import 'apify.dart';
import 'gemini.dart';
import 'providers.dart';

/// The keys that can make notes: Gemini (several, taken in turn) for video, OpenAI and Claude from frames.
class AnalysisKeys {
  final List<String> gemini;
  final String? openai;
  final String? claude;
  const AnalysisKeys({this.gemini = const [], this.openai, this.claude});
  bool get isEmpty => gemini.isEmpty && openai == null && claude == null;
}

class _NoGemini implements Exception {}

/// Leave the item queued for the next run (network, 429/5xx, Instagram pause, bad key).
class _RetryLater implements Exception {
  final String reason;
  final bool stopAll;
  _RetryLater(this.reason, {this.stopAll = false});
}

/// Processes `pending_items` into library notes (IMPLEMENTATION §2.5). Runs on app open and in the background task.
class Runner {
  final CounterBridge bridge;
  final LibraryDb library;
  final http.Client client;
  final Future<AnalysisKeys> Function() keys;
  final Future<String?> Function() apifyKey;
  final Future<int> Function() readTurn;
  final Future<void> Function(int) saveTurn;
  final Gemini Function(String key) makeGemini;
  final Directory tempDir;
  final int Function() now;

  /// Why the last run left items queued or failed one, for the library screen. Null when the last run was clean.
  String? lastProblem;

  /// Title of the note the current item produced, passed to Kotlin for the digest.
  String _title = '';

  /// Notes made by the last run, for the "note ready" notification.
  final finishedTitles = <String>[];

  late AnalysisKeys _keys;
  int _turn = 0;
  int _itemTurn = 0;
  final _badKeys = <String>{};

  Runner({
    required this.bridge,
    required this.library,
    required this.client,
    required this.keys,
    required this.apifyKey,
    Future<int> Function()? readTurn,
    Future<void> Function(int)? saveTurn,
    Gemini Function(String key)? makeGemini,
    Directory? tempDir,
    int Function()? now,
  })  : readTurn = readTurn ?? (() async => 0),
        saveTurn = saveTurn ?? ((_) async {}),
        makeGemini = makeGemini ?? ((k) => Gemini(client, k)),
        tempDir = tempDir ?? Directory.systemTemp,
        now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Returns how many items were finished this run.
  Future<int> processQueue() async {
    _keys = await keys();
    if (_keys.isEmpty) return 0; // Items stay queued; the library asks for a key.
    if (!await library.tryLock(now())) {
      lastProblem = 'Another analysis run is in progress (it holds the queue for up to 5 min).';
      return 0;
    }
    var finished = 0;
    lastProblem = null;
    finishedTitles.clear();
    _badKeys.clear();
    _turn = await readTurn();
    try {
      for (final item in await bridge.pendingItems(status: 'queued')) {
        try {
          _title = '';
          _itemTurn = _turn++; // one reel per key: the next reel starts on the next key
          final status = await _process(item);
          await bridge.setPendingStatus(item.id, status, title: _title);
          if (_title.isNotEmpty) finishedTitles.add(_title);
          finished++;
        } on _RetryLater catch (e) {
          lastProblem = 'Will retry: ${e.reason}';
          if (e.stopAll) break;
        } catch (e) {
          // Errors too, not just Exceptions: an uncaught one used to leave the item queued with no reason shown.
          lastProblem = 'Failed: $e';
          await bridge.setPendingStatus(item.id, 'failed');
        }
      }
    } finally {
      await saveTurn(_turn);
      await library.unlock();
    }
    return finished;
  }

  /// Runs [f] with this reel's Gemini key; on a rate limit or a bad key, the next key gets a go.
  Future<T> _gemini<T>(Future<T> Function(Gemini g) f) async {
    final ks = _keys.gemini;
    GeminiException? last;
    for (var i = 0; i < ks.length; i++) {
      final k = ks[(_itemTurn + i) % ks.length];
      if (_badKeys.contains(k)) continue;
      try {
        return await f(makeGemini(k));
      } on GeminiException catch (e) {
        if (e.kind == GeminiFailure.rejected) rethrow;
        if (e.kind == GeminiFailure.badKey) _badKeys.add(k);
        last = e;
      }
    }
    throw last ?? _NoGemini();
  }

  List<ChatModel> get _others => [
        if (_keys.openai != null) ChatModel('openai', _keys.openai!, client),
        if (_keys.claude != null) ChatModel('claude', _keys.claude!, client),
      ];

  /// OpenAI / Claude, in that order, for when Gemini can't (no key, all keys limited).
  Future<Analysis> _viaOthers(String context, List<List<int>> images, Object? geminiError) async {
    Object? last = geminiError;
    for (final m in _others) {
      try {
        return await m.analyse(context, images);
      } on GeminiException catch (e) {
        if (e.kind == GeminiFailure.rejected) rethrow;
        last = e;
      }
    }
    if (last is GeminiException) throw last;
    throw GeminiException(GeminiFailure.retryLater, 'no provider could take this reel');
  }

  Future<Analysis> _video(File f, String context) async {
    Object? err;
    try {
      return await _gemini((g) => g.video(f, context: context));
    } on _NoGemini {
      // fall through to frames
    } on GeminiException catch (e) {
      if (e.kind == GeminiFailure.rejected || _others.isEmpty) rethrow;
      err = e;
    }
    // ponytail: 6 frames, no audio; Gemini stays the only provider that hears the reel.
    return _viaOthers(context, await bridge.videoFrames(f.path), err);
  }

  Future<Analysis> _captionAndThumbnail(String text, List<int>? jpeg) async {
    Object? err;
    try {
      return await _gemini((g) => g.captionAndThumbnail(text: text, jpeg: jpeg));
    } on _NoGemini {
      // fall through
    } on GeminiException catch (e) {
      if (e.kind == GeminiFailure.rejected || _others.isEmpty) rethrow;
      err = e;
    }
    return _viaOthers('Caption and thumbnail only (no video available).\n$text', [?jpeg], err);
  }

  Future<String> _process(PendingItem item) async {
    if (item.url.isEmpty) return item.author.isEmpty && item.caption.isEmpty && item.onScreenText.isEmpty ? 'failed' : await _textOnly(item);
    if (await library.has(item.url)) return 'done'; // shared twice
    try {
      return switch (item.app) {
        'youtube' => await _youtube(item),
        'photo' => await _photo(item),
        _ => await _instagram(item),
      };
    } on GeminiException catch (e) {
      if (e.kind == GeminiFailure.badKey) throw _RetryLater('Your key was rejected (${e.message.split(':').first}). Check it in Settings.', stopAll: true);
      if (e.kind == GeminiFailure.retryLater) throw _RetryLater(e.toString());
      rethrow;
    } on RateLimited {
      throw _RetryLater('Instagram is limiting requests right now. Reel Bot retries on its own (10–30 min).');
    } on SocketException catch (e) {
      throw _RetryLater('no network ($e)');
    } on http.ClientException catch (e) {
      throw _RetryLater('network error ($e)');
    }
  }

  /// v0.8: shared photos. The image stays in app storage, so the note can show it.
  Future<String> _photo(PendingItem item) async {
    final f = File(item.url.substring('photo:'.length));
    if (!await f.exists()) return 'failed';
    final context = item.caption.isEmpty ? '' : 'Shared with: ${item.caption}';
    await _save(item, await _pictures([await f.readAsBytes()], context), 'done', 0, caption: item.caption);
    return 'done';
  }

  /// Gemini for pictures, else OpenAI / Claude (they take images too).
  Future<Analysis> _pictures(List<List<int>> jpegs, String context) async {
    Object? err;
    try {
      return await _gemini((g) => g.images(jpegs, context: context));
    } on _NoGemini {
      // fall through
    } on GeminiException catch (e) {
      if (e.kind == GeminiFailure.rejected || _others.isEmpty) rethrow;
      err = e;
    }
    return _viaOthers('Pictures, not a video (${jpegs.length}). $context', jpegs, err);
  }

  Future<String> _youtube(PendingItem item) async {
    try {
      await _save(item, await _gemini((g) => g.youtube(item.url)), 'done', 0);
      return 'done';
    } on _NoGemini {
      // only Gemini can watch a YouTube link; the others get the title and thumbnail
    } on GeminiException catch (e) {
      if (e.kind != GeminiFailure.rejected) rethrow; // limited: wait for Gemini rather than settle for a thumbnail
    }
    // YT-OEMBED: Gemini refused the URL (private, unlisted, or the free daily cap).
    final r = await client.get(Uri.parse('https://www.youtube.com/oembed?url=${Uri.encodeComponent(item.url)}&format=json'));
    if (r.statusCode != 200) return 'failed';
    final o = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final author = '${o['author_name'] ?? ''}';
    final a = await _captionAndThumbnail('Channel: $author\nTitle: ${o['title'] ?? ''}', await _bytes('${o['thumbnail_url'] ?? ''}'));
    await _save(item, a, 'caption+thumbnail', 0, author: author, caption: '${o['title'] ?? ''}');
    return 'caption+thumbnail';
  }

  Future<String> _instagram(PendingItem item) async {
    IgFetch f;
    try {
      f = await bridge.fetchInstagram(item.url);
    } on PlatformException {
      f = const IgFetch();
    }
    var author = f.author.isEmpty ? item.author : f.author;
    var caption = f.caption.isEmpty ? item.caption : f.caption;
    var thumb = f.thumbnailUrl;
    var step = f.step;
    var videoPath = f.videoPath;

    final apify = videoPath == null ? await apifyKey() : null;
    final code = RegExp(r'instagram\.com/(?:reel|reels|p|tv)/([A-Za-z0-9_-]+)').firstMatch(item.url)?.group(1);
    if (apify != null && code != null) {
      ApifyResult? a;
      try {
        a = await apifyFetch(client, apify, code);
      } on Exception {
        a = null; // bad key, no credit or timeout: carry on with what the cascade found
      }
      if (a != null) {
        if (author.isEmpty) author = a.author;
        if (caption.isEmpty) caption = a.caption;
        if (thumb.isEmpty) thumb = a.thumbnailUrl;
        if (a.videoUrl.isNotEmpty) videoPath = await _download(a.videoUrl, code);
        if (videoPath != null || step == 0) step = 7; // Apify, after the six Kotlin steps
      }
    }

    final context = [
      if (author.isNotEmpty) 'Author: @$author',
      if (caption.isNotEmpty) 'Caption: $caption',
      if (item.onScreenText.isNotEmpty) 'On screen: ${item.onScreenText}',
    ].join('\n');

    if (videoPath != null) {
      final file = File(videoPath);
      try {
        await _save(item, await _video(file, context), 'done', step, author: author, caption: caption);
        return 'done';
      } on GeminiException catch (e) {
        if (e.kind != GeminiFailure.rejected) rethrow;
      } finally {
        if (await file.exists()) await file.delete(); // only text is kept
      }
    }
    // v0.8: a photo post or carousel: every picture, so the note covers the whole post, not just its cover.
    if (videoPath == null && f.images.isNotEmpty) {
      final pics = [for (final u in f.images.take(10)) ?await _bytes(u)];
      if (pics.isNotEmpty) {
        await _save(item, await _pictures(pics, context), 'done', step, author: author, caption: caption);
        return 'done';
      }
    }
    if (caption.isNotEmpty || thumb.isNotEmpty) {
      final a = await _captionAndThumbnail(context, await _bytes(thumb));
      await _save(item, a, 'caption+thumbnail', step, author: author, caption: caption);
      return 'caption+thumbnail';
    }
    if (author.isNotEmpty || item.onScreenText.isNotEmpty) return _textOnly(item, author: author, step: step);
    return 'failed';
  }

  /// Instagram posts where only the author could be found (and URL-less rows from before v0.9.0).
  Future<String> _textOnly(PendingItem item, {String? author, int step = 0}) async {
    final who = author ?? item.author;
    final a = await _captionAndThumbnail('Author: @$who\nCaption: ${item.caption}\nOn screen: ${item.onScreenText}', null);
    await _save(item, a, 'text-only', step, author: who, caption: item.caption);
    return 'text-only';
  }

  Future<void> _save(PendingItem item, Analysis a, String analysis, int step, {String author = '', String caption = ''}) =>
      library.saveReel(Reel(
        url: item.url.isEmpty ? 'local:${item.id}' : item.url,
        app: item.app,
        title: _title = a.title.isEmpty ? (caption.isEmpty ? 'Untitled reel' : caption.split('\n').first) : a.title,
        summary: a.summary,
        keyPoints: a.keyPoints,
        tags: a.tags,
        author: author,
        caption: caption,
        analysis: analysis,
        step: step,
        savedAt: item.createdAt == 0 ? now() : item.createdAt,
      ));

  Future<List<int>?> _bytes(String url) async {
    if (url.isEmpty) return null;
    try {
      final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      return r.statusCode == 200 ? r.bodyBytes : null;
    } on Exception {
      return null;
    }
  }

  /// Apify's video link, downloaded now (CDN links expire). 100 MB cap, as in IG-CDN.
  Future<String?> _download(String url, String code) async {
    final f = File('${tempDir.path}/apify-$code.mp4');
    try {
      final r = await client.send(http.Request('GET', Uri.parse(url))..headers['Referer'] = 'https://www.instagram.com/');
      if (r.statusCode != 200) return null;
      final sink = f.openWrite();
      var total = 0;
      await for (final chunk in r.stream) {
        total += chunk.length;
        if (total > 100 * 1024 * 1024) {
          await sink.close();
          await f.delete();
          return null;
        }
        sink.add(chunk);
      }
      await sink.close();
      return f.path;
    } on Exception {
      return null;
    }
  }
}
