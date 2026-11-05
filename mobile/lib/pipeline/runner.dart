import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../data/library_db.dart';
import '../native/counter_bridge.dart';
import 'apify.dart';
import 'gemini.dart';

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
  final Future<String?> Function() geminiKey;
  final Future<String?> Function() apifyKey;
  final Gemini Function(String key) makeGemini;
  final Directory tempDir;
  final int Function() now;

  /// Why the last run left items queued or failed one, for the library screen. Null when the last run was clean.
  String? lastProblem;

  Runner({
    required this.bridge,
    required this.library,
    required this.client,
    required this.geminiKey,
    required this.apifyKey,
    Gemini Function(String key)? makeGemini,
    Directory? tempDir,
    int Function()? now,
  })  : makeGemini = makeGemini ?? ((k) => Gemini(client, k)),
        tempDir = tempDir ?? Directory.systemTemp,
        now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Returns how many items were finished this run.
  Future<int> processQueue() async {
    final key = await geminiKey();
    if (key == null) return 0; // Items stay queued; the library shows "Add your Gemini key".
    if (!await library.tryLock(now())) {
      lastProblem = 'Another analysis run is in progress (it holds the queue for up to 5 min).';
      return 0;
    }
    var finished = 0;
    lastProblem = null;
    try {
      final gemini = makeGemini(key);
      for (final item in await bridge.pendingItems(status: 'queued')) {
        try {
          await bridge.setPendingStatus(item.id, await _process(item, gemini));
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
      await library.unlock();
    }
    return finished;
  }

  Future<String> _process(PendingItem item, Gemini gemini) async {
    if (item.url.isEmpty) return item.author.isEmpty && item.caption.isEmpty ? 'failed' : await _textOnly(item, gemini);
    if (await library.has(item.url)) return 'done'; // shared twice
    try {
      return item.app == 'youtube' ? await _youtube(item, gemini) : await _instagram(item, gemini);
    } on GeminiException catch (e) {
      if (e.kind == GeminiFailure.badKey) throw _RetryLater('Gemini rejected your key. Check it in Settings.', stopAll: true);
      if (e.kind == GeminiFailure.retryLater) throw _RetryLater(e.toString());
      rethrow;
    } on RateLimited {
      throw _RetryLater('Instagram is pausing requests from this phone; trying again in up to 30 min.');
    } on SocketException catch (e) {
      throw _RetryLater('no network ($e)');
    } on http.ClientException catch (e) {
      throw _RetryLater('network error ($e)');
    }
  }

  Future<String> _youtube(PendingItem item, Gemini gemini) async {
    try {
      await _save(item, await gemini.youtube(item.url), 'done', 0);
      return 'done';
    } on GeminiException catch (e) {
      if (e.kind != GeminiFailure.rejected) rethrow;
    }
    // YT-OEMBED: Gemini refused the URL (private, unlisted, or the free daily cap).
    final r = await client.get(Uri.parse('https://www.youtube.com/oembed?url=${Uri.encodeComponent(item.url)}&format=json'));
    if (r.statusCode != 200) return 'failed';
    final o = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final author = '${o['author_name'] ?? ''}';
    final a = await gemini.captionAndThumbnail(
        text: 'Channel: $author\nTitle: ${o['title'] ?? ''}', jpeg: await _bytes('${o['thumbnail_url'] ?? ''}'));
    await _save(item, a, 'caption+thumbnail', 0, author: author, caption: '${o['title'] ?? ''}');
    return 'caption+thumbnail';
  }

  Future<String> _instagram(PendingItem item, Gemini gemini) async {
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
        if (videoPath != null || step == 0) step = 6;
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
        await _save(item, await gemini.video(file, context: context), 'done', step, author: author, caption: caption);
        return 'done';
      } on GeminiException catch (e) {
        if (e.kind != GeminiFailure.rejected) rethrow;
      } finally {
        if (await file.exists()) await file.delete(); // only text is kept
      }
    }
    if (caption.isNotEmpty || thumb.isNotEmpty) {
      final a = await gemini.captionAndThumbnail(text: context, jpeg: await _bytes(thumb));
      await _save(item, a, 'caption+thumbnail', step, author: author, caption: caption);
      return 'caption+thumbnail';
    }
    if (author.isNotEmpty || item.onScreenText.isNotEmpty) return _textOnly(item, gemini);
    return 'failed';
  }

  Future<String> _textOnly(PendingItem item, Gemini gemini) async {
    final a = await gemini.captionAndThumbnail(
        text: 'Author: @${item.author}\nCaption: ${item.caption}\nOn screen: ${item.onScreenText}');
    await _save(item, a, 'text-only', 0, author: item.author, caption: item.caption);
    return 'text-only';
  }

  Future<void> _save(PendingItem item, Analysis a, String analysis, int step, {String author = '', String caption = ''}) =>
      library.saveReel(Reel(
        url: item.url.isEmpty ? 'local:${item.id}' : item.url,
        app: item.app,
        title: a.title.isEmpty ? (caption.isEmpty ? 'Untitled reel' : caption.split('\n').first) : a.title,
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
