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

  static const version = '0.5.1';

  /// Providers the user has a key for, in the order the chat offers them.
  Future<List<String>> chatProviders() async => [
        if ((await keys.geminiKeys).isNotEmpty) 'gemini',
        if (await keys.openai != null) 'openai',
        if (await keys.claude != null) 'claude',
        if (await keys.groq != null) 'groq',
      ];

  /// The saved notes for one question, trimmed to save tokens: the 8 best matches in full, the next 32 as
  /// title + summary. A question with no matching words ("summarise everything") gets every title + summary.
  Future<String> notesContext(String question) async {
    final all = await library.reels();
    final words = question.toLowerCase().split(RegExp(r'\W+')).where((w) => w.length > 3).toSet();
    // ponytail: keyword overlap, no embeddings; good enough for a personal library.
    int score(Reel r) => words.where('${r.title} ${r.summary} ${r.keyPoints} ${r.tags}'.toLowerCase().contains).length;
    final ranked = [...all]..sort((a, b) => score(b).compareTo(score(a)));
    final matched = ranked.where((r) => score(r) > 0).toList();
    String brief(Reel r) => '- ${r.title} [${r.tags.join(', ')}]: ${r.summary}';
    if (matched.isEmpty) return all.map(brief).join('\n');
    return [
      for (final r in matched.take(8)) '${brief(r)} Points: ${r.keyPoints.join('; ')} (${r.url})',
      for (final r in matched.skip(8).take(32)) brief(r),
    ].join('\n');
  }

  /// One chat turn from the user's saved notes. Gemini tries each saved key in turn on a rate limit.
  Future<String> chat(String provider, List<String> turns) async {
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
        return await ChatModel(provider, k, client).complete(system, turns);
      } on GeminiException catch (e) {
        if (e.kind == GeminiFailure.rejected) rethrow;
        last = e;
      }
    }
    throw last ?? GeminiException(GeminiFailure.badKey, 'Add a ${ChatModel.labels[provider]} key in Settings');
  }
}
