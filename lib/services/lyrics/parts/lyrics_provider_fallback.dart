import 'dart:convert';
import 'package:http/http.dart' as http;
import '../lyrics_matcher.dart';
import '../lyrics_service.dart';

class LyricsProviderFallback {
  /// JioSaavn lyrics endpoint with [songId] percent-encoded so a hostile
  /// id cannot smuggle extra query parameters or fragments into the URL.
  /// Public so deterministic tests can pin the exact wire shape.
  static Uri jioSaavnLyricsUri(String songId) => Uri.parse(
      'https://www.jiosaavn.com/api.php?__call=lyrics.getLyrics&_format=json&_marker=0&cc=in&lyrics_id=${Uri.encodeComponent(songId)}');

  static Future<LyricsData?> fetchMusixmatchLyrics(
      String cleanTitle, String primaryArtist, String rawTitle) async {
    try {
      final query = Uri.encodeComponent('$rawTitle $primaryArtist');
      final uri = Uri.parse('https://lrclib.net/api/search?q=$query');
      final res = await http.get(uri, headers: {
        'User-Agent': 'Noctra/1.0.6 (https://noctra.app)'
      }).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List?;
        if (list != null && list.isNotEmpty) {
          final matches = list.where((it) {
            final t = (it['trackName'] as String?) ?? '';
            return LyricsMatcher.titlesMatch(rawTitle, t);
          }).toList();

          for (final item in matches) {
            final synced = item['syncedLyrics'] as String?;
            if (synced != null && synced.isNotEmpty) {
              final lines = LyricsMatcher.parseLrc(synced);
              if (lines.isNotEmpty) {
                return LyricsData(
                    isSynced: true,
                    lines: lines,
                    plainText: item['plainLyrics'] ?? synced);
              }
            }
            final plain = item['plainLyrics'] as String?;
            if (plain != null && plain.trim().isNotEmpty) {
              return LyricsData(
                  isSynced: false, lines: const [], plainText: plain.trim());
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<LyricsData?> fetchJioSaavnLyrics(
      String rawTitle, String cleanTitle, String primaryArtist) async {
    try {
      final searchUri = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=autocomplete.get&_format=json&_marker=0&cc=in&includeMetaTags=1&query=${Uri.encodeComponent('$cleanTitle $primaryArtist')}',
      );
      final sRes = await http.get(searchUri, headers: {
        'User-Agent': 'Mozilla/5.0'
      }).timeout(const Duration(seconds: 4));
      if (sRes.statusCode == 200) {
        final sData = jsonDecode(sRes.body);
        final songsList = (sData['songs']?['data'] as List?) ?? [];
        for (final item in songsList) {
          final songId = item['id']?.toString() ?? '';
          final jiosaavnTitle = (item['title'] as String?) ?? '';
          final titleMatch = songId.isNotEmpty &&
              jiosaavnTitle.isNotEmpty &&
              LyricsMatcher.titlesMatch(rawTitle, jiosaavnTitle);
          if (titleMatch) {
            final lyrUri = jioSaavnLyricsUri(songId);
            final lRes = await http.get(lyrUri, headers: {
              'User-Agent': 'Mozilla/5.0'
            }).timeout(const Duration(seconds: 4));
            if (lRes.statusCode == 200) {
              final lData = jsonDecode(lRes.body);
              final rawLyr = lData['lyrics'] as String?;
              if (rawLyr != null && rawLyr.isNotEmpty) {
                final clean = rawLyr
                    .replaceAll('<br>', '\n')
                    .replaceAll('&quot;', '"')
                    .replaceAll('&amp;', '&')
                    .replaceAll('<p>', '')
                    .replaceAll('</p>', '')
                    .replaceAll('<strong>', '')
                    .replaceAll('</strong>', '')
                    .replaceAll('<i>', '')
                    .replaceAll('</i>', '')
                    .replaceAll('<br/>', '\n')
                    .replaceAll('<BR/>', '\n')
                    .replaceAll('<BR>', '\n')
                    .replaceAll('<br />', '\n')
                    .replaceAll(RegExp(r'<[^>]+>'), '')
                    .trim();
                if (clean.isNotEmpty && LyricsMatcher.isValidLyrics(clean)) {
                  return LyricsData(
                      isSynced: false,
                      lines: const [],
                      plainText: clean,
                      source: 'jiosaavn');
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Zero-key fallback using Letras.mus.br (strong Latin, Spanish, Portuguese,
  /// and English catalog, no Cloudflare challenge).
  static Future<LyricsData?> fetchLetrasLyrics(
      String rawTitle, String cleanTitle, String primaryArtist) async {
    try {
      final q = '${cleanTitle.isNotEmpty ? cleanTitle : rawTitle} $primaryArtist'
          .trim();
      if (q.isEmpty) return null;
      final searchUri = Uri.parse(
        'https://solr.sscdn.co/letras/m1/?q=${Uri.encodeComponent(q)}&wt=json',
      );
      final sRes = await http
          .get(searchUri, headers: const {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 5));
      if (sRes.statusCode != 200) return null;

      var body = sRes.body.trim();
      if (body.startsWith('LetrasSug(') && body.endsWith(')')) {
        body = body.substring('LetrasSug('.length, body.length - 1);
      }
      final decoded = jsonDecode(body);
      final docs = (decoded['response']?['docs'] as List?) ?? const [];
      for (final doc in docs) {
        if (doc is! Map) continue;
        final dns = doc['dns']?.toString() ?? '';
        final urlSlug = doc['url']?.toString() ?? '';
        final docTitle = doc['txt']?.toString() ?? doc['full_txt']?.toString() ?? '';
        final docArtist = doc['art']?.toString() ?? '';
        if (dns.isEmpty || urlSlug.isEmpty) continue;
        final titleOk = LyricsMatcher.titlesMatch(rawTitle, docTitle) ||
            LyricsMatcher.titlesMatch(cleanTitle, docTitle);
        final artistOk = primaryArtist.isEmpty ||
            LyricsMatcher.artistMatches(primaryArtist, docArtist);
        if (!titleOk || !artistOk) continue;

        final pageUri = Uri.parse('https://www.letras.mus.br/$dns/$urlSlug/');
        final pRes = await http
            .get(pageUri, headers: const {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 5));
        if (pRes.statusCode != 200) continue;

        final m = RegExp(
          r'<div[^>]*class="lyric-original[^"]*"[^>]*>([\s\S]*?)</div>',
          caseSensitive: false,
        ).firstMatch(pRes.body);
        if (m == null) continue;
        final clean = m.group(1)!
            .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
            .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll('&amp;', '&')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'")
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim();
        if (clean.isNotEmpty && LyricsMatcher.isValidLyrics(clean)) {
          return LyricsData(
            isSynced: false,
            lines: const [],
            plainText: clean,
            source: 'letras',
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Zero-key fallback using AZLyrics deterministic artist/title URLs
  /// (e.g. `https://www.azlyrics.com/lyrics/anuelaa/sexonama.html`).
  static Future<LyricsData?> fetchAzLyrics(
    String rawTitle,
    String cleanTitle,
    String primaryArtist, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      final artistSlug = _azSlug(primaryArtist);
      if (artistSlug.isEmpty) return null;
      final candidates = <String>{
        _azSlug(cleanTitle),
        _azSlug(rawTitle),
      }..removeWhere((s) => s.isEmpty);

      for (final titleSlug in candidates) {
        final uri = Uri.parse(
            'https://www.azlyrics.com/lyrics/$artistSlug/$titleSlug.html');
        final res = await httpClient.get(uri, headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        }).timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) continue;

        final html = utf8.decode(res.bodyBytes, allowMalformed: true);
        final extracted = extractAzLyricsFromHtml(html);
        if (extracted.isNotEmpty && LyricsMatcher.isValidLyrics(extracted)) {
          return LyricsData(
            isSynced: false,
            lines: const [],
            plainText: extracted,
            source: 'azlyrics',
          );
        }
      }
    } catch (_) {} finally {
      if (ownsClient) httpClient.close();
    }
    return null;
  }

  static String _azSlug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String extractAzLyricsFromHtml(String html) {
    final m = RegExp(
      r'<!--\s*Usage of azlyrics\.com content by any third-party[\s\S]*?-->([\s\S]*?)</div>',
      caseSensitive: false,
    ).firstMatch(html);
    if (m == null) return '';
    return m
        .group(1)!
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
