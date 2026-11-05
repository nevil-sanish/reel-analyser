import 'package:http/http.dart' as http;

import 'data/key_store.dart';
import 'data/library_db.dart';
import 'native/counter_bridge.dart';
import 'pipeline/gemini.dart';
import 'pipeline/runner.dart';

/// Everything the UI and the background task share. One per engine.
class AppServices {
  final KeyStore keys;
  final LibraryDb library;
  final CounterBridge bridge;
  final http.Client client;
  final Runner runner;

  AppServices._(this.keys, this.library, this.bridge, this.client)
      : runner = Runner(bridge: bridge, library: library, client: client, geminiKey: () => keys.gemini, apifyKey: () => keys.apify);

  static Future<AppServices> create() async =>
      AppServices._(KeyStore(), await LibraryDb.open(), CounterBridge(), http.Client());

  /// Answers from the user's own notes, with their own key.
  Future<String> ask(String question) async {
    final key = await keys.gemini;
    if (key == null) return 'Add your Gemini API key in Settings first.';
    final words = question.toLowerCase().split(RegExp(r'\W+')).where((w) => w.length > 3);
    final all = await library.reels();
    // ponytail: keyword overlap picks the notes; switch to embeddings if libraries get big.
    int score(r) => words.where((w) => '${r.title} ${r.summary} ${r.keyPoints} ${r.tags}'.toLowerCase().contains(w)).length;
    final ranked = [...all]..sort((a, b) => score(b).compareTo(score(a)));
    final notes = ranked.take(40).map((r) => '- ${r.title} (${r.url}): ${r.summary} ${r.keyPoints.join('; ')}').join('\n');
    if (notes.isEmpty) return 'Your library is empty. Share a reel to Reel Bot first.';
    return Gemini(client, key).ask('Answer the question using only these saved notes. '
        'Cite the note titles you used. If the notes do not cover it, say so.\n\nNotes:\n$notes\n\nQuestion: $question');
  }
}
