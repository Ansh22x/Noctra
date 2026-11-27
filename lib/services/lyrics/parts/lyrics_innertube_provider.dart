import 'dart:convert';
import 'package:http/http.dart' as http;
import '../lyrics_service.dart';

class LyricsInnertubeProvider {
  static const _clientContext = {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': '1.20240820.01.00',
      'hl': 'en',
      'gl': 'US',
    }
  };

  static Future<LyricsData?> fetchInnerTubeLyrics(
      String rawSongId, String title, String artist) async {
    try {
      String videoId = rawSongId
          .replaceFirst('ytdlp_', '')
          .replaceFirst('yt_', '');

      if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
        videoId = await _searchVideoId('$title $artist'.trim()) ?? '';
      }
      if (videoId.length != 11) return null;

      final nextRes = await http
          .post(
            Uri.parse('https://music.youtube.com/youtubei/v1/next'),
            body: jsonEncode({'videoId': videoId, 'context': _clientContext}),
            headers: const {
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (nextRes.statusCode != 200) return null;

      final nextData = jsonDecode(nextRes.body);
      final tabs = nextData['contents']
                  ?['singleColumnMusicWatchNextResultsRenderer']
              ?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']
          as List?;
      final lyricsTab = tabs?.cast<Map?>().firstWhere(
        (t) {
          final tab = t?['tabRenderer'];
          final bid = tab?['endpoint']?['browseEndpoint']?['browseId']
                  ?.toString() ??
              '';
          return tab?['title'] == 'Lyrics' ||
              bid.startsWith('MPLYt_') ||
              bid.startsWith('FE');
        },
        orElse: () => null,
      );
      final browseId = lyricsTab?['tabRenderer']?['endpoint']
          ?['browseEndpoint']?['browseId'] as String?;
      if (browseId == null || browseId.isEmpty) return null;

      final bRes = await http
          .post(
            Uri.parse('https://music.youtube.com/youtubei/v1/browse'),
            body: jsonEncode({'browseId': browseId, 'context': _clientContext}),
            headers: const {
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (bRes.statusCode != 200) return null;

      final bData = jsonDecode(bRes.body);
      // 1. Check for synced timedLyricsRenderer
      final timed = _extractTimedLyrics(bData);
      if (timed != null) return timed;

      // 2. Fallback to plain musicDescriptionShelfRenderer
      final desc = bData['contents']?['sectionListRenderer']?['contents']?[0]
              ?['musicDescriptionShelfRenderer']?['description']?['runs']
          as List?;
      if (desc != null && desc.isNotEmpty) {
        final fullText = desc.map((r) => r['text'] ?? '').join('').trim();
        if (fullText.isNotEmpty) {
          return LyricsData(
            isSynced: false,
            lines: const [],
            plainText: fullText,
            source: 'ytmusic',
          );
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _searchVideoId(String query) async {
    if (query.isEmpty) return null;
    try {
      final res = await http
          .post(
            Uri.parse('https://music.youtube.com/youtubei/v1/search'),
            body: jsonEncode({
              'query': query,
              'params': 'EgWKAQIIAWoMEAMQBBAJEAoQBRAV',
              'context': _clientContext,
            }),
            headers: const {
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final m = RegExp(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"')
          .firstMatch(res.body);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  static LyricsData? _extractTimedLyrics(dynamic bData) {
    try {
      final timedList = bData['contents']?['sectionListRenderer']?['contents']
          ?[0]?['timedLyricsRenderer']?['timedLyricsData'] as List?;
      if (timedList == null || timedList.isEmpty) return null;
      final lines = <LyricLine>[];
      for (final item in timedList) {
        final text = (item['lyricLine'] as String?)?.trim() ?? '';
        final ms = int.tryParse(
            item['cueRange']?['startTimeMilliseconds']?.toString() ?? '');
        if (text.isNotEmpty && ms != null) {
          lines.add(LyricLine(
            timestamp: Duration(milliseconds: ms),
            text: text,
          ));
        }
      }
      if (lines.isEmpty) return null;
      return LyricsData(
        isSynced: true,
        lines: lines,
        plainText: lines.map((l) => l.text).join('\n'),
        source: 'ytmusic',
      );
    } catch (_) {
      return null;
    }
  }
}
