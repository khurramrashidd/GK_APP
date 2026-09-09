import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/gemini_config.dart';

/// Calls Gemini's generateContent endpoint to produce a deep, concept-level
/// explanation for a single quiz question. Stateless, single-shot.
class GeminiService {
  Future<String> explainQuestion({
    required String question,
    required List<String> options,
    required int correctIndex,
    String? shortExplanation,
  }) async {
    if (!GeminiConfig.isConfigured) {
      throw StateError('AI review is not configured yet.');
    }

    final correct = (correctIndex >= 0 && correctIndex < options.length)
        ? options[correctIndex]
        : '(unknown)';

    final optionsBlock = [
      for (var i = 0; i < options.length; i++)
        '${String.fromCharCode(65 + i)}. ${options[i]}'
    ].join('\n');

    final prompt = '''
You are an expert tutor for Indian competitive exams. A student just answered
this multiple-choice question. Explain the underlying concept and theory clearly
and concisely so they truly understand it — not just why the answer is correct.

Question: $question

Options:
$optionsBlock

Correct answer: $correct
${shortExplanation != null && shortExplanation.isNotEmpty ? 'Existing note: $shortExplanation' : ''}

Write a focused explanation (about 120-180 words). Cover the key concept, one or
two facts worth remembering, and a common mistake to avoid. Use plain text with
short paragraphs. Do not use markdown headings.''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.4,
        'thinkingConfig': {'thinkingLevel': 'low'}
      }
    });

    final resp = await http.post(
      Uri.parse(GeminiConfig.endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': GeminiConfig.apiKey,
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception('Gemini error ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini returned no content.');
    }
    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    final text = parts
        ?.map((p) => (p as Map<String, dynamic>)['text'] ?? '')
        .join('')
        .toString()
        .trim();

    if (text == null || text.isEmpty) {
      throw Exception('Gemini returned an empty explanation.');
    }
    return text;
  }
}
