import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lyrics_matcher.dart';
import 'lyrics_service.dart';

/// Translates non-English synced and plain-text lyrics into the target
/// language (default: English `'en'`) without requiring an API key.
class LyricsTranslationService {
  static final Map<String, LyricsData> _cache = {};
  static const int _maxCacheSize = 100;

  static const Set<String> _englishWords = {
    'the', 'and', 'you', 'i', 'to', 'a', 'is', 'in', 'it', 'of', 'my', 'me',
    'that', 'for', 'on', 'with', 'we', 'be', 'this', 'not', 'are', 'but',
    'what', 'all', 'your', 'so', 'just', 'like', 'know', "don't", "i'm",
    'love', 'never', 'when', 'feel', 'out', 'up', 'down', 'got', 'can',
    'will', 'from', 'have', 'was', 'were', 'they', 'she', 'he', 'her', 'his',
  };

  static const Set<String> _nonEnglishLatinWords = {
    // Spanish / Portuguese / French / Italian / German
    'que', 'de', 'la', 'el', 'en', 'un', 'una', 'por', 'con', 'para', 'pero',
    'como', 'más', 'te', 'mi', 'tu', 'se', 'los', 'las', 'yo', 'sin', 'vida',
    'corazón', 'amor', 'noche', 'je', 'il', 'elle', 'nous', 'vous', 'est',
    'pas', 'dans', 'pour', 'avec', 'mais', 'qui', 'tout', 'mon', 'ton', 'ich',
    'und', 'der', 'die', 'das', 'nicht', 'ein', 'eine', 'ist', 'du', 'wir',
    'che', 'non', 'sono', 'per', 'mio', 'tua', 'não', 'você',
    'com', 'meu', 'minha',
    // Romanized Hindi / Punjabi / Urdu
    'hai', 'main', 'mein', 'dil', 'pyaar', 'pyar', 'tere', 'mere', 'tera',
    'mera', 'kyun', 'nahi', 'yaar', 'ishq', 'tujhe', 'mujhe', 'hum', 'tum',
    'aaj', 'kal', 'raat', 'bhi', 'kuch', 'koi', 'jab', 'tab', 'ho',
  };

  /// Heuristic check for whether [text] is likely non-English.
  static bool isLikelyNonEnglishText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (LyricsMatcher.hasNonLatinScript(trimmed)) return true;

    // Non-ASCII Latin diacritics or Spanish punctuation strongly indicate non-English.
    if (RegExp(r'[¿¡áéíóúüñçàèêëîïôöùûãõßžščřďťňłśźżăâîșț]',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return true;
    }

    final words = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r"[^\p{L}'\s]", unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return false;

    int enHits = 0;
    int nonEnHits = 0;
    for (final w in words) {
      if (_englishWords.contains(w)) enHits++;
      if (_nonEnglishLatinWords.contains(w)) nonEnHits++;
    }

    if (nonEnHits >= 2 && nonEnHits >= enHits) return true;
    if (words.length >= 8 && enHits == 0 && nonEnHits >= 1) return true;
    return false;
  }

  static bool isLikelyNonEnglish(LyricsData data) {
    final sample = data.lines.isNotEmpty
        ? data.lines.take(12).map((l) => l.text).join(' ')
        : data.plainText;
    return isLikelyNonEnglishText(sample);
  }

  static void clearCacheForTest() => _cache.clear();

  /// Translates [data] line-by-line into [targetLang] (default `'en'`).
  /// Existing `LyricLine.translation` values are preserved unless empty.
  static Future<LyricsData> translateLyrics(
    LyricsData data, {
    String songId = '',
    String targetLang = 'en',
    bool force = false,
    http.Client? client,
  }) async {
    if (!force && !isLikelyNonEnglish(data)) return data;

    final cacheKey = '${songId}_$targetLang';
    if (songId.isNotEmpty && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      if (data.isSynced && data.lines.isNotEmpty) {
        final alreadyTranslated = data.lines
            .where((l) => l.translation != null && l.translation!.trim().isNotEmpty)
            .length;
        if (alreadyTranslated >= (data.lines.length * 0.5).ceil()) {
          return data;
        }

        final sourceTexts = data.lines.map((l) => l.text).toList();
        final translatedTexts = await _translateBatch(
          sourceTexts,
          targetLang: targetLang,
          client: httpClient,
        );

        final updatedLines = List<LyricLine>.generate(data.lines.length, (i) {
          final line = data.lines[i];
          if (line.translation != null && line.translation!.trim().isNotEmpty) {
            return line;
          }
          final tr = i < translatedTexts.length ? translatedTexts[i].trim() : '';
          final sameAsOriginal =
              tr.toLowerCase() == line.text.trim().toLowerCase();
          return LyricLine(
            timestamp: line.timestamp,
            text: line.text,
            translation: (tr.isNotEmpty && !sameAsOriginal) ? tr : null,
          );
        });

        final result = LyricsData(
          isSynced: data.isSynced,
          lines: updatedLines,
          plainText: data.plainText,
          source: data.source,
          translatedPlainText: updatedLines
              .map((l) => l.translation ?? l.text)
              .join('\n'),
        );
        _putCache(cacheKey, result);
        return result;
      }

      if (data.plainText.trim().isNotEmpty) {
        final rawLines = data.plainText.split('\n');
        final translated = await _translateBatch(
          rawLines,
          targetLang: targetLang,
          client: httpClient,
        );
        final joined = translated.join('\n').trim();
        if (joined.isEmpty ||
            joined.toLowerCase() == data.plainText.trim().toLowerCase()) {
          return data;
        }
        final result = LyricsData(
          isSynced: false,
          lines: data.lines,
          plainText: data.plainText,
          source: data.source,
          translatedPlainText: joined,
        );
        _putCache(cacheKey, result);
        return result;
      }

      return data;
    } catch (_) {
      return data;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static void _putCache(String key, LyricsData value) {
    if (key.startsWith('_')) return;
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  static Future<List<String>> _translateBatch(
    List<String> lines, {
    required String targetLang,
    required http.Client client,
  }) async {
    final output = List<String>.from(lines);
    const maxChunkChars = 1200;
    const maxChunkLines = 22;

    int start = 0;
    while (start < lines.length) {
      int end = start;
      int charCount = 0;
      while (end < lines.length && (end - start) < maxChunkLines) {
        final nextLen = lines[end].length + 1;
        if (end > start && charCount + nextLen > maxChunkChars) break;
        charCount += nextLen;
        end++;
      }

      final chunk = lines.sublist(start, end);
      final nonEmptyIndices = <int>[];
      final nonEmptyLines = <String>[];
      for (int i = 0; i < chunk.length; i++) {
        if (chunk[i].trim().isNotEmpty) {
          nonEmptyIndices.add(i);
          nonEmptyLines.add(chunk[i].trim());
        }
      }

      if (nonEmptyLines.isNotEmpty) {
        final translatedChunk = await _callGoogleTranslate(
          nonEmptyLines.join('\n'),
          targetLang: targetLang,
          client: client,
        );
        if (translatedChunk != null) {
          final splitLines = translatedChunk.split('\n');
          if (splitLines.length == nonEmptyLines.length) {
            for (int k = 0; k < nonEmptyIndices.length; k++) {
              output[start + nonEmptyIndices[k]] = splitLines[k].trim();
            }
          }
        }
      }

      start = end;
    }

    return output;
  }

  static Future<String?> _callGoogleTranslate(
    String text, {
    required String targetLang,
    required http.Client client,
  }) async {
    try {
      final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
        'client': 'gtx',
        'sl': 'auto',
        'tl': targetLang,
        'dt': 't',
        'q': text,
      });
      final res = await client
          .get(uri, headers: const {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final detectedLang =
          decoded.length > 2 ? decoded[2]?.toString().toLowerCase() : null;
      if (detectedLang == targetLang.toLowerCase()) {
        return null;
      }

      final sentences = decoded[0];
      if (sentences is! List) return null;
      final buf = StringBuffer();
      for (final seg in sentences) {
        if (seg is List && seg.isNotEmpty && seg[0] != null) {
          buf.write(seg[0].toString());
        }
      }
      final result = buf.toString();
      return result.trim().isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }
}
