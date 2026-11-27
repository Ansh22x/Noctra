import 'dart:convert';
import 'package:http/http.dart' as http;
import '../lyrics_matcher.dart';
import '../lyrics_service.dart';

/// Fetches high-accuracy, human-curated plain lyrics from Genius.
///
/// Works zero-key by default via Genius's public multi-search endpoint and
/// HTML lyrics containers, with optional Bearer token support for the official
/// Genius API when configured by the user.
class LyricsGeniusProvider {
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/html;q=0.9,*/*;q=0.8',
  };

  static Future<LyricsData?> fetchGeniusLyrics(
    String rawTitle,
    String cleanTitle,
    String primaryArtist, {
    String? apiToken,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      final songUrl = await searchGeniusUrl(
        rawTitle,
        cleanTitle,
        primaryArtist,
        apiToken: apiToken,
        client: httpClient,
      );
      if (songUrl == null || songUrl.isEmpty) return null;

      final pageRes = await httpClient
          .get(Uri.parse(songUrl), headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (pageRes.statusCode != 200) return null;

      final extracted = extractLyricsFromHtml(pageRes.body);
      if (extracted.isEmpty || !LyricsMatcher.isValidLyrics(extracted)) {
        return null;
      }

      return LyricsData(
        isSynced: false,
        lines: const [],
        plainText: extracted,
        source: 'genius',
      );
    } catch (_) {
      return null;
    } finally {
      if (ownsClient) {
        httpClient.close();
      }
    }
  }

  static Future<String?> searchGeniusUrl(
    String rawTitle,
    String cleanTitle,
    String primaryArtist, {
    String? apiToken,
    required http.Client client,
  }) async {
    final queryText =
        '${cleanTitle.isNotEmpty ? cleanTitle : rawTitle} $primaryArtist'.trim();
    if (queryText.isEmpty) return null;

    final token = apiToken?.trim();
    if (token != null && token.isNotEmpty) {
      final apiUri = Uri.parse(
        'https://api.genius.com/search?q=${Uri.encodeComponent(queryText)}',
      );
      final res = await client.get(
        apiUri,
        headers: {
          ..._headers,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final hits = (data['response']?['hits'] as List?) ?? const [];
        final url = _pickBestHitUrl(hits, rawTitle, cleanTitle, primaryArtist);
        if (url != null) return url;
      }
    }

    final publicUri = Uri.parse(
      'https://genius.com/api/search/multi?per_page=5&q=${Uri.encodeComponent(queryText)}',
    );
    final res = await client
        .get(publicUri, headers: _headers)
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    final sections = (data['response']?['sections'] as List?) ?? const [];
    for (final section in sections) {
      final type = section['type']?.toString() ?? '';
      if (type != 'song' && type != 'top_hit') continue;
      final hits = (section['hits'] as List?) ?? const [];
      final url = _pickBestHitUrl(hits, rawTitle, cleanTitle, primaryArtist);
      if (url != null) return url;
    }
    return null;
  }

  static String? _pickBestHitUrl(
    List<dynamic> hits,
    String rawTitle,
    String cleanTitle,
    String primaryArtist,
  ) {
    for (final hit in hits) {
      if (hit is! Map) continue;
      if (hit['type'] != null && hit['type'] != 'song') continue;
      final result = hit['result'];
      if (result is! Map) continue;

      final title = result['title']?.toString() ?? '';
      final artist = result['primary_artist']?['name']?.toString() ??
          result['artist_names']?.toString() ??
          '';
      final url = result['url']?.toString() ?? '';
      if (url.isEmpty || title.isEmpty) continue;

      final titleOk = LyricsMatcher.titlesMatch(rawTitle, title) ||
          LyricsMatcher.titlesMatch(cleanTitle, title);
      final artistOk = primaryArtist.isEmpty ||
          LyricsMatcher.artistMatches(primaryArtist, artist);

      if (titleOk && artistOk) {
        return url;
      }
    }
    return null;
  }

  /// Extracts clean lyrics text from Genius HTML pages.
  /// Public for deterministic unit testing.
  static String extractLyricsFromHtml(String html) {
    if (html.isEmpty) return '';

    final chunks = <String>[];
    final startTagRe = RegExp(
      r'<div[^>]*data-lyrics-container="true"[^>]*>',
      caseSensitive: false,
    );
    for (final m in startTagRe.allMatches(html)) {
      final inner = _extractBalancedDivInner(html, m.end);
      if (inner.isNotEmpty) {
        chunks.add(_cleanHtmlFragment(inner));
      }
    }

    if (chunks.isEmpty) {
      final legacyMatch = RegExp(
        r'<div[^>]*class="lyrics"[^>]*>([\s\S]*?)</div>',
        caseSensitive: false,
      ).firstMatch(html);
      if (legacyMatch != null) {
        chunks.add(_cleanHtmlFragment(legacyMatch.group(1) ?? ''));
      }
    }

    final joined = chunks.where((c) => c.trim().isNotEmpty).join('\n');
    return joined
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _extractBalancedDivInner(String html, int contentStart) {
    final tagRe = RegExp(r'<(/?)div\b[^>]*>', caseSensitive: false);
    int depth = 1;
    for (final m in tagRe.allMatches(html, contentStart)) {
      final isClose = m.group(1) == '/';
      depth += isClose ? -1 : 1;
      if (depth == 0) {
        return html.substring(contentStart, m.start);
      }
    }
    return '';
  }

  static String _cleanHtmlFragment(String fragment) {
    var text = fragment
        .replaceAll(RegExp(r'<div[^>]*data-exclude-from-selection="true"[^>]*>[\s\S]*?</div>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');

    text = _decodeHtmlEntities(text);
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  static String _decodeHtmlEntities(String input) {
    var out = input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '', radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    return out;
  }
}
