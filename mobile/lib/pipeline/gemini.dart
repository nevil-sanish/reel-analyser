import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Why a Gemini call failed, so the runner knows whether to retry later.
enum GeminiFailure {
  /// 429, 5xx or network: leave the item queued.
  retryLater,

  /// The key is missing or wrong: leave queued and tell the user.
  badKey,

  /// Gemini refused this input (e.g. a private/unlisted YouTube URL or the free 8 h/day cap).
  rejected,
}

class GeminiException implements Exception {
  final GeminiFailure kind;
  final String message;
  GeminiException(this.kind, this.message);
  @override
  String toString() => 'Gemini ${kind.name}: $message';
}

/// The structured note Gemini returns for one reel.
class Analysis {
  final String title;
  final String summary;
  final List<String> keyPoints;
  final List<String> tags;
  const Analysis(this.title, this.summary, this.keyPoints, this.tags);
}

/// GEM-GENERATE, GEM-UPLOAD / GEM-FILE-GET / GEM-FILE-DELETE (ENDPOINTS §3).
class Gemini {
  static const base = 'https://generativelanguage.googleapis.com';
  static const models = ['gemini-3.5-flash', 'gemini-3.5-flash-lite'];
  static const inlineLimit = 20 * 1024 * 1024;

  /// Thinking levels to try per model, best first; null = send no thinking config.
  static const _levels = <String?>['low', null];

  /// Learnt per process: the first level index each model accepted.
  static final _acceptedLevel = <String, int>{};

  final http.Client client;
  final String key;
  final Duration pollEvery;
  Gemini(this.client, this.key, {this.pollEvery = const Duration(seconds: 2)});

  static const _prompt = '''You turn a short social video (an Instagram Reel or YouTube Short) into a study note.
Watch and listen to all of it, including on-screen text. Write in the video's language.
Return JSON: title (a short descriptive title, not clickbait), summary (2–4 sentences on what it actually teaches or shows),
keyPoints (3–8 concrete takeaways: steps, numbers, names, recipes, claims), tags (3–6 lowercase single-word topics).
If it is a caption and thumbnail only, say so in the summary and work from what is there.''';

  static final _schema = {
    'type': 'OBJECT',
    'properties': {
      'title': {'type': 'STRING'},
      'summary': {'type': 'STRING'},
      'keyPoints': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'tags': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
    },
    'required': ['title', 'summary', 'keyPoints', 'tags'],
  };

  Map<String, String> get _headers => {'x-goog-api-key': key, 'Content-Type': 'application/json'};

  Future<Analysis> youtube(String shortsUrl) =>
      _analyse([{'fileData': {'fileUri': shortsUrl, 'mimeType': 'video/*'}}]);

  Future<Analysis> video(File f, {String context = ''}) async {
    final ctx = [if (context.isNotEmpty) {'text': context}];
    if (await f.length() <= inlineLimit) {
      return _analyse([{'inlineData': {'mimeType': 'video/mp4', 'data': base64Encode(await f.readAsBytes())}}, ...ctx]);
    }
    final file = await _upload(f);
    try {
      return await _analyse([{'fileData': {'fileUri': file['uri'], 'mimeType': 'video/mp4'}}, ...ctx]);
    } finally {
      // Files expire after 48 h anyway; a failed delete isn't worth failing the item.
      await client.delete(Uri.parse('$base/v1beta/${file['name']}'), headers: _headers).catchError((_) => http.Response('', 0));
    }
  }

  /// Caption + thumbnail: used when no video could be fetched.
  Future<Analysis> captionAndThumbnail({required String text, List<int>? jpeg}) => _analyse([
        if (jpeg != null) {'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(jpeg)}},
        {'text': 'Caption and thumbnail only (no video available).\n$text'},
      ]);

  /// Free-form text answer, for "Ask your library".
  Future<String> ask(String prompt) async {
    final j = await _generate(models.first, {'contents': [{'parts': [{'text': prompt}]}]});
    return _text(j);
  }

  Future<Analysis> _analyse(List<Map<String, Object?>> parts) async {
    GeminiException? last;
    for (final model in models) {
      for (var i = _acceptedLevel[model] ?? 0; i < _levels.length; i++) {
        final level = _levels[i];
        final body = {
          'contents': [{'parts': [...parts, {'text': _prompt}]}],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': _schema,
            if (level != null) 'thinkingConfig': {'thinkingLevel': level},
          },
        };
        try {
          final j = jsonDecode(_text(await _generate(model, body))) as Map<String, Object?>;
          _acceptedLevel[model] = i;
          List<String> list(Object? v) => v is List ? v.map((e) => '$e').toList() : [];
          return Analysis('${j['title'] ?? ''}', '${j['summary'] ?? ''}', list(j['keyPoints']), list(j['tags']));
        } on GeminiException catch (e) {
          if (e.kind != GeminiFailure.rejected) rethrow;
          last = e; // 400: try the next thinking level, then the next model.
        } on FormatException catch (e) {
          last = GeminiException(GeminiFailure.rejected, 'bad JSON: ${e.message}');
        }
      }
    }
    throw last!;
  }

  Future<Map<String, Object?>> _generate(String model, Map<String, Object?> body) async {
    final http.Response r;
    try {
      r = await client
          .post(Uri.parse('$base/v1beta/models/$model:generateContent'), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(minutes: 3));
    } on Exception catch (e) {
      throw GeminiException(GeminiFailure.retryLater, '$e');
    }
    if (r.statusCode == 200) return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
    throw _failure(r);
  }

  static GeminiException _failure(http.Response r) {
    final msg = 'HTTP ${r.statusCode}: ${r.body.length > 300 ? r.body.substring(0, 300) : r.body}';
    if (r.statusCode == 429 || r.statusCode >= 500) return GeminiException(GeminiFailure.retryLater, msg);
    if (r.statusCode == 401 || r.body.contains('API key not valid') || r.body.contains('API_KEY_INVALID')) {
      return GeminiException(GeminiFailure.badKey, msg);
    }
    return GeminiException(GeminiFailure.rejected, msg);
  }

  static String _text(Map<String, Object?> j) {
    final parts = ((j['candidates'] as List?)?.firstOrNull as Map?)?['content']?['parts'] as List? ?? [];
    return parts.where((p) => p['thought'] != true).map((p) => p['text'] ?? '').join();
  }

  /// Resumable upload, then poll until ACTIVE (max 120 s).
  Future<Map<String, Object?>> _upload(File f) async {
    final len = await f.length();
    final start = await client.post(Uri.parse('$base/upload/v1beta/files'),
        headers: {
          ..._headers,
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'start',
          'X-Goog-Upload-Header-Content-Length': '$len',
          'X-Goog-Upload-Header-Content-Type': 'video/mp4',
        },
        body: jsonEncode({'file': {'display_name': f.uri.pathSegments.last}}));
    final uploadUrl = start.headers['x-goog-upload-url'];
    if (start.statusCode != 200 || uploadUrl == null) throw _failure(start);
    final up = await client.post(Uri.parse(uploadUrl),
        headers: {'X-Goog-Upload-Offset': '0', 'X-Goog-Upload-Command': 'upload, finalize'}, body: await f.readAsBytes());
    if (up.statusCode != 200) throw _failure(up);
    var file = (jsonDecode(up.body) as Map)['file'] as Map<String, Object?>;
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (file['state'] != 'ACTIVE') {
      if (file['state'] == 'FAILED') throw GeminiException(GeminiFailure.rejected, 'file processing failed');
      if (DateTime.now().isAfter(deadline)) throw GeminiException(GeminiFailure.retryLater, 'file not ACTIVE after 120 s');
      await Future<void>.delayed(pollEvery);
      final g = await client.get(Uri.parse('$base/v1beta/${file['name']}'), headers: _headers);
      if (g.statusCode != 200) throw _failure(g);
      file = jsonDecode(g.body) as Map<String, Object?>;
    }
    return file;
  }
}
