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
          readTurn: () => keys.geminiTurn,
          saveTurn: keys.setGeminiTurn,
        );

  static Future<AppServices> create() async =>
      AppServices._(KeyStore(), await LibraryDb.open(), CounterBridge(), http.Client());

  static const version = '0.9.5';

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

  /// Notes from before v0.9.2 have no overview bullets; these can be re-analysed into the new format.
  Future<List<Reel>> oldFormatNotes() async =>
      [for (final r in await library.reels()) if (r.overview.isEmpty && !r.url.startsWith('local:')) r];

  /// Re-queues every old-format note (see [retry]); returns how many went back in the queue.
  Future<int> reanalyseOld() async {
    var n = 0;
    for (final r in await oldFormatNotes()) {
      if (await retry(r)) n++;
    }
    return n;
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

  /// The saved notes for one question. Every note you haven't deleted counts, archived ones included.
  /// The 12 best keyword matches go in full (overview, key points, mentions); the rest as title + overview.
  /// A question with no matching words ("what have I saved?") gets title + overview for every note.
  Future<String> notesContext(String question) async {
    final all = await library.reels(); // no filter: library + archive; deleted notes are gone from the DB
    final words = question.toLowerCase().split(RegExp(r'\W+')).where((w) => w.length > 3).toSet();
    String text(Reel r) => '${r.title} ${r.overview} ${r.summary} ${r.keyPoints} ${r.mentions} ${r.tags}'.toLowerCase();
    // ponytail: keyword overlap, no embeddings; good enough for a personal library.
    int score(Reel r) => words.where(text(r).contains).length;
    final ranked = [...all]..sort((a, b) => score(b).compareTo(score(a)));
    String brief(Reel r) =>
        '- ${r.title} (${r.kind}, ${savedAgo(r.savedAt, DateTime.now())}): ${r.overview.isEmpty ? r.summary : r.overview.join('; ')}';
    String full(Reel r) => [
          brief(r),
          if (r.keyPoints.isNotEmpty) '  Points: ${r.keyPoints.join('; ')}',
          if (r.mentions.isNotEmpty) '  Mentioned: ${r.mentions.join(', ')}',
          if (r.url.startsWith('http')) '  Link: ${r.url}',
        ].join('\n');
    final matched = ranked.where((r) => score(r) > 0).toList();
    if (matched.isEmpty) return all.map(brief).join('\n');
    return [for (final r in matched.take(12)) full(r), for (final r in matched.skip(12).take(40)) brief(r)].join('\n');
  }

  /// One chat turn from the user's saved notes. Gemini tries each saved key in turn on a rate limit.
  Future<String> chat(String provider, List<String> turns, {String? model}) async {
    final notes = await notesContext(turns.last);
    if (notes.isEmpty) return 'Your library is empty. Share a reel to Reel Bot first.';
    final system = 'You are Reel Bot. Answer from the user\'s saved reel notes below. Cite note titles you used. '
        'If the notes do not cover it, say so briefly. Keep answers short.\n\nSaved notes:\n$notes';
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
