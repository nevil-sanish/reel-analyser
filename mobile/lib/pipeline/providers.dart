import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gemini.dart';

/// One chat-capable provider and the user's key for it. Raw HTTP: Dart has no official SDKs for these.
class ChatModel {
  final String provider; // gemini, openai, claude, groq
  final String key;
  final http.Client client;

  /// One of [models] for this provider; null = its cheapest.
  final String? model;
  const ChatModel(this.provider, this.key, this.client, {this.model});

  static const labels = {'gemini': 'Gemini', 'openai': 'OpenAI', 'claude': 'Claude', 'groq': 'Groq'};
  String get label => labels[provider] ?? provider;

  /// Per provider, cheapest first (the default, token cost first), then one stronger option for the chat picker.
  static const models = {
    'gemini': {'gemini-3.5-flash-lite': '3.5 Flash-Lite · cheapest', 'gemini-3.6-flash': '3.6 Flash · smarter'},
    'openai': {'gpt-6-luna': 'GPT-6 Luna · cheapest', 'gpt-6.1-terra': 'GPT-6.1 Terra · smarter'},
    'claude': {'claude-haiku-5-5': 'Haiku 5.5 · cheapest', 'claude-sonnet-5-5': 'Sonnet 5.5 · smarter'},
    'groq': {'openai/gpt-oss-20b': 'gpt-oss 20B · cheapest', 'openai/gpt-oss-120b': 'gpt-oss 120B · smarter'},
  };
  String get modelId => model ?? models[provider]!.keys.first;

  /// Only these can look at pictures; Groq is for chat only.
  bool get seesImages => provider != 'groq';

  /// `turns` alternate user / assistant, starting and ending with the user. `images` (JPEG) go with the last turn.
  Future<String> complete(String system, List<String> turns, {List<List<int>> images = const []}) {
    return switch (provider) {
      'gemini' => _gemini(system, turns, images),
      'claude' => _claude(system, turns, images),
      // Cheapest models that still read images well enough for short notes; the user put token cost first.
      'openai' => _openaiCompatible('https://api.openai.com/v1/chat/completions', modelId, system, turns, images,
          extra: {'reasoning_effort': 'none'}),
      _ => _openaiCompatible('https://api.groq.com/openai/v1/chat/completions', modelId, system, turns, const [],
          extra: {'reasoning_effort': 'low'}),
    };
  }

  Future<String> _gemini(String system, List<String> turns, List<List<int>> images) async {
    final r = await _post(Uri.parse('${Gemini.base}/v1beta/models/$modelId:generateContent'),
        {'x-goog-api-key': key}, {
      'systemInstruction': {'parts': [{'text': system}]},
      'contents': [
        for (var i = 0; i < turns.length; i++)
          {
            'role': i.isEven ? 'user' : 'model',
            'parts': [
              if (i == turns.length - 1)
                for (final j in images) {'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(j)}},
              {'text': turns[i]},
            ],
          },
      ],
      'generationConfig': {'thinkingConfig': {'thinkingLevel': 'minimal'}, 'mediaResolution': 'MEDIA_RESOLUTION_LOW'},
    });
    final parts = (((r['candidates'] as List?)?.firstOrNull as Map?)?['content'] as Map?)?['parts'] as List? ?? [];
    return parts.where((p) => p['thought'] != true).map((p) => p['text'] ?? '').join();
  }

  Future<String> _claude(String system, List<String> turns, List<List<int>> images) async {
    final r = await _post(Uri.parse('https://api.anthropic.com/v1/messages'), {
      'x-api-key': key,
      'anthropic-version': '2026-10-21',
    }, {
      // Haiku at low effort with thinking off: the user asked for the cheapest setup that still writes good notes.
      // Sonnet 5.5 rejects disabled thinking, so it runs adaptive at low effort.
      'model': modelId,
      'max_tokens': 16000,
      'system': system,
      if (modelId.contains('haiku')) 'thinking': {'type': 'disabled'},
      'output_config': {'effort': 'low'},
      'messages': [
        for (var i = 0; i < turns.length; i++)
          {
            'role': i.isEven ? 'user' : 'assistant',
            'content': [
              if (i == turns.length - 1)
                for (final j in images)
                  {'type': 'image', 'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Encode(j)}},
              {'type': 'text', 'text': turns[i]},
            ],
          },
      ],
    });
    if (r['stop_reason'] == 'refusal') throw GeminiException(GeminiFailure.rejected, 'Claude declined this request');
    return (r['content'] as List? ?? []).where((b) => b['type'] == 'text').map((b) => b['text']).join();
  }

  Future<String> _openaiCompatible(String url, String model, String system, List<String> turns, List<List<int>> images,
      {Map<String, Object?> extra = const {}}) async {
    final r = await _post(Uri.parse(url), {'Authorization': 'Bearer $key'}, {
      'model': model,
      ...extra,
      'messages': [
        {'role': 'system', 'content': system},
        for (var i = 0; i < turns.length; i++)
          {
            'role': i.isEven ? 'user' : 'assistant',
            'content': i == turns.length - 1 && images.isNotEmpty
                ? [
                    for (final j in images) {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(j)}', 'detail': 'low'}},
                    {'type': 'text', 'text': turns[i]},
                  ]
                : turns[i],
          },
      ],
    });
    return '${(((r['choices'] as List?)?.firstOrNull as Map?)?['message'] as Map?)?['content'] ?? ''}';
  }

  Future<Map<String, Object?>> _post(Uri url, Map<String, String> headers, Map<String, Object?> body) async {
    final http.Response r;
    try {
      r = await client
          .post(url, headers: {...headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(minutes: 3));
    } on Exception catch (e) {
      throw GeminiException(GeminiFailure.retryLater, '$label: $e');
    }
    final text = utf8.decode(r.bodyBytes);
    final msg = '$label HTTP ${r.statusCode}: ${text.length > 300 ? text.substring(0, 300) : text}';
    if (r.statusCode == 200) return jsonDecode(text) as Map<String, Object?>;
    if (r.statusCode == 401 || r.statusCode == 403) throw GeminiException(GeminiFailure.badKey, msg);
    if (r.statusCode == 429 || r.statusCode >= 500) throw GeminiException(GeminiFailure.retryLater, msg);
    throw GeminiException(GeminiFailure.rejected, msg);
  }

  /// A note from frames or a thumbnail, for providers without video input.
  Future<Analysis> analyse(String context, List<List<int>> images) async {
    final out = await complete('${Gemini.prompt}\nReply with only a JSON object with those four keys.',
        ['${images.isEmpty ? 'No pictures.' : '${images.length} frames from the video, in order.'}\n$context'],
        images: seesImages ? images : const []);
    return Gemini.parseAnalysis(out);
  }
}
