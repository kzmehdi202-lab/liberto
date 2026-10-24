import 'dart:convert';

import 'package:http/http.dart' as http;

/// A model available on OpenRouter.
class OpenRouterModel {
  OpenRouterModel({
    required this.id,
    required this.name,
    this.contextLength,
  });

  final String id;
  final String name;
  final int? contextLength;

  @override
  String toString() => name;
}

/// Client for the OpenRouter API (OpenAI-compatible).
class OpenRouterService {
  static const String _baseUrl = 'https://openrouter.ai/api/v1';

  /// Fetches all models available on OpenRouter (no key required).
  Future<List<OpenRouterModel>> fetchModels() async {
    final uri = Uri.parse('$_baseUrl/models');
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch models: HTTP ${res.statusCode}');
    }
    final dynamic body = jsonDecode(res.body);
    final List data = body['data'] ?? const [];
    return data
        .map((e) => OpenRouterModel(
              id: e['id'] as String,
              name: (e['name'] as String?) ?? (e['id'] as String),
              contextLength: (e['context_length'] as num?)?.toInt(),
            ))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Sends a chat completion request with streaming (SSE).
  /// Calls [onToken] for each text delta. Returns the full text.
  Future<String> streamChat({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required void Function(String token) onToken,
    String? systemPrompt,
    int connectTimeoutSeconds = 30,
  }) async {
    final client = http.Client();
    final controller = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    final req = http.Request('POST', Uri.parse('$_baseUrl/chat/completions'))
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://aichat.app',
        'X-Title': 'AI Chat',
      })
      ..body = jsonEncode({
        'model': model,
        'messages': controller,
        'stream': true,
      });

    final streamed = await client
        .send(req)
        .timeout(Duration(seconds: connectTimeoutSeconds));

    if (streamed.statusCode != 200) {
      final errBody =
          await streamed.stream.transform(utf8.decoder).join();
      client.close();
      final msg = _extractErrorMessage(errBody);
      throw Exception(msg ?? 'HTTP ${streamed.statusCode}');
    }

    final completer = _BufferCompleter();
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      final lines = chunk.split('\n');
      for (final raw in lines) {
        final line = raw.trim();
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') continue;
        try {
          final dynamic obj = jsonDecode(payload);
          final delta =
              obj['choices']?[0]?['delta']?['content'] as String?;
          if (delta != null && delta.isNotEmpty) {
            completer.append(delta);
            onToken(delta);
          }
        } catch (_) {
          // ignore malformed keep-alive lines
        }
      }
    }
    client.close();
    return completer.text;
  }

  static String? _extractErrorMessage(String body) {
    try {
      final dynamic obj = jsonDecode(body);
      return obj['error']?['message'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// Collects streamed text pieces.
class _BufferCompleter {
  final _buf = StringBuffer();

  void append(String s) => _buf.write(s);

  String get text => _buf.toString();
}
