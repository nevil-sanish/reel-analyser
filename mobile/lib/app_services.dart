import 'package:http/http.dart' as http;

import 'core/models.dart';
import 'data/key_store.dart';
import 'data/library_db.dart';
import 'native/counter_bridge.dart';
import 'pipeline/gemini.dart';
import 'pipeline/providers.dart';
import 'pipeline/runner.dart';

/// Everything the UI and the background task share. One per engine.
class AppServices {
  final KeyStore keys;
  final LibraryDb library;
  final CounterBridge bridge;
  final http.Client client;
  final Runner runner;

  AppServices._(this.keys, this.library, this.bridge, this.client)
      : runner = Runner(
          bridge: bridge,
          library: library,
          client: client,
          keys: () async => AnalysisKeys(gemini: await keys.geminiKeys, openai: await keys.openai, claude: await keys.claude),
          apifyKey: () => keys.apify,
          readTurn: library.geminiTurn,
          saveTurn: library.setGeminiTurn,
        );

  static Future<AppServices> create() async =>
      AppServices._(KeyStore(), await LibraryDb.open(), CounterBridge(), http.Client());

  static const version = '0.9.8';

  /// Sends a note made without the video back through the queue: its queue row goes back to queued and
  /// the note is removed, so the runner doesn't skip the link as already saved. Returns false if there's no row.
  Future<bool> retry(Reel r) async {
    final rows = (await bridge.pendingItems()).where((p) => p.url == r.url).toList();
    if (rows.isEmpty) return false;
    for (final p in rows) {
      await bridge.setPendingStatus(p.id, 'queued');
    }
    await library.delete(r.url);
    return true;
  }

  /// Deletes shared-photo files that no note and no queued item uses any more (a deleted photo note keeps
  /// its file until the next start, so Undo can still show it).
  Future<void> sweepPhotos() async {
    String? path(String url) => url.startsWith('photo:') ? url.substring('photo:'.length) : null;
    final keep = {
      for (final r in await library.reels()) ?path(r.url),
      for (final p in await bridge.pendingItems(status: 'queued')) ?path(p.url),
    };
    await bridge.sweepPhotos(keep.toList());
  }

  /// v0.6.2 added the Instagram embed-player step; Instagram notes made from text only get one more go.
  Future<void> retryTextOnlyOnce() async {
    if (await keys.flag('retried_062')) return;
    for (final r in await library.reels()) {
      if (r.app == 'instagram' && r.analysis == 'text-only') await retry(r);
    }
    await keys.setFlag('retried_062');
  }

  /// Providers the user has a key for, in the order the chat offers them.
  Future<List<String>> chatProviders() async => [
        if ((await keys.geminiKeys).isNotEmpty) 'gemini',
        if (await keys.openai != null) 'openai',
        if (await keys.claude != null) 'claude',
        if (await keys.groq != null) 'groq',
      ];

  /// Every saved note (library and archive; deleted ones are gone) with everything the app kept about it:
  /// overview, summary, key points, mentions, transcript, on-screen text, caption, author and link.
  /// Notes that match the question's words come first. A size cap keeps the request within a model's window:
  /// notes past it fall back to title + overview.
  Future<String> notesContext(String question, {int budget = 300000}) async {
    final all = await library.reels();
    final words = question.toLowerCase().split(RegExp(r'\W+')).where((w) => w.length > 3).toSet();
    String text(Reel r) =>
        '${r.title} ${r.overview} ${r.summary} ${r.keyPoints} ${r.mentions} ${r.tags} ${r.transcript} ${r.onScreenText} ${r.caption}'.toLowerCase();
    // ponytail: keyword overlap, no embeddings; good enough for a personal library.
    int score(Reel r) => words.where(text(r).contains).length;
    final ranked = [...all]..sort((a, b) => score(b).compareTo(score(a)));
    String brief(Reel r) =>
        '- ${r.title} (${r.kind}, ${savedAgo(r.savedAt, DateTime.now())}): ${r.overview.isEmpty ? r.summary : r.overview.join('; ')}';
    String full(Reel r) => [
          brief(r),
          if (r.overview.isNotEmpty && r.summary.isNotEmpty) '  Detail: ${r.summary}',
          if (r.keyPoints.isNotEmpty) '  Points: ${r.keyPoints.join('; ')}',
          if (r.mentions.isNotEmpty) '  Mentioned: ${r.mentions.join(', ')}',
          if (r.author.isNotEmpty) '  Author: @${r.author}',
          if (r.caption.isNotEmpty) '  Caption: ${r.caption}',
          if (r.onScreenText.isNotEmpty) '  On screen: ${r.onScreenText}',
          if (r.transcript.isNotEmpty) '  Transcript: ${r.transcript}',
          if (r.url.startsWith('http')) '  Link: ${r.url}',
        ].join('\n');
    final out = <String>[];
    var used = 0;
    for (final r in ranked) {
      final f = full(r);
      if (used + f.length <= budget) {
        out.add(f);
        used += f.length;
      } else {
        out.add(brief(r));
      }
    }
    return out.join('\n');
  }

  /// One chat turn from the user's saved notes. Gemini tries each saved key in turn on a rate limit.
  Future<String> chat(String provider, List<String> turns, {String? model}) async {
    final notes = await notesContext(turns.last);
    if (notes.isEmpty) return 'Your library is empty. Share a reel to Reel Analyser first.';
    final system = 'You are Reel Analyser. The saved reel notes below are everything you know: answer ONLY from them, '
        'never from general knowledge. Cite the note titles you used. If the notes do not cover the question, '
        'say that they do not and stop. Keep answers short.\n\nSaved notes:\n$notes';
    final ks = switch (provider) {
      'gemini' => await keys.geminiKeys,
      'openai' => [?await keys.openai],
      'claude' => [?await keys.claude],
      _ => [?await keys.groq],
    };
    GeminiException? last;
    for (final k in ks) {
      try {
        return await ChatModel(provider, k, client, model: model).complete(system, turns);
      } on GeminiException catch (e) {
        if (e.kind == GeminiFailure.rejected) rethrow;
        last = e;
      }
    }
    throw last ?? GeminiException(GeminiFailure.badKey, 'Add a ${ChatModel.labels[provider]} key in Settings');
  }
}
