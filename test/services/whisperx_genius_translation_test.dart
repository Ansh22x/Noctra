import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noctra/data/models/song_model.dart';
import 'package:noctra/services/lyrics/lyrics_service.dart';
import 'package:noctra/services/lyrics/lyrics_translation_service.dart';
import 'package:noctra/services/lyrics/parts/lyrics_genius_provider.dart';
import 'package:noctra/services/lyrics/parts/lyrics_whisperx_provider.dart';

void main() {
  group('Genius Lyrics Provider', () {
    test('extractLyricsFromHtml parses data-lyrics-container and entities', () {
      const html = '''
      <html><body>
        <div data-lyrics-container="true">
          <div data-exclude-from-selection="true">Contributors</div>
          [Verse 1]<br/>
          Hello &amp; welcome to the night<br/>
          <a href="/annotation">It&#x27;s a &quot;dream&quot;</a>
        </div>
        <div data-lyrics-container="true">
          [Chorus]<br/>
          Under neon lights
        </div>
      </body></html>
      ''';
      final extracted = LyricsGeniusProvider.extractLyricsFromHtml(html);
      expect(extracted, contains('[Verse 1]'));
      expect(extracted, contains('Hello & welcome to the night'));
      expect(extracted, contains('It\'s a "dream"'));
      expect(extracted, contains('[Chorus]'));
      expect(extracted, contains('Under neon lights'));
      expect(extracted, isNot(contains('Contributors')));
    });

    test('fetchGeniusLyrics searches public API and extracts song page', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'genius.com' &&
            req.url.path.contains('/api/search/multi')) {
          return http.Response(
            jsonEncode({
              'response': {
                'sections': [
                  {
                    'type': 'song',
                    'hits': [
                      {
                        'type': 'song',
                        'result': {
                          'title': 'Midnight City',
                          'primary_artist': {'name': 'M83'},
                          'url': 'https://genius.com/M83-midnight-city-lyrics',
                        }
                      }
                    ]
                  }
                ]
              }
            }),
            200,
          );
        }
        if (req.url.toString() == 'https://genius.com/M83-midnight-city-lyrics') {
          return http.Response(
            '<div data-lyrics-container="true">Waiting in a car<br/>Waiting for a ride in the dark</div>',
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final data = await LyricsGeniusProvider.fetchGeniusLyrics(
        'Midnight City',
        'Midnight City',
        'M83',
        client: client,
      );

      expect(data, isNotNull);
      expect(data!.source, 'genius');
      expect(data.isSynced, isFalse);
      expect(data.plainText, contains('Waiting in a car'));
      expect(data.plainText, contains('Waiting for a ride in the dark'));
    });
  });

  group('WhisperX Forced Alignment & Sync', () {
    test('alignReferenceLinesToSegments aligns Genius lines monotonically', () {
      final refLines = [
        'Waiting in a car',
        'Waiting for a ride in the dark',
        'The night city grows',
      ];
      const segments = [
        WhisperXSegment(
          start: Duration(seconds: 5),
          end: Duration(seconds: 8),
          text: 'waiting in a car',
        ),
        WhisperXSegment(
          start: Duration(seconds: 15),
          end: Duration(seconds: 19),
          text: 'the night city grows',
        ),
      ];

      final aligned =
          WhisperXSyncService.alignReferenceLinesToSegments(refLines, segments);
      expect(aligned.length, 3);
      expect(aligned[0].timestamp, const Duration(seconds: 5));
      expect(aligned[0].text, 'Waiting in a car');
      // Middle unmatched line should be interpolated between 5s and 15s -> 10s
      expect(aligned[1].timestamp, const Duration(seconds: 10));
      expect(aligned[2].timestamp, const Duration(seconds: 15));
    });

    test('syncWithWhisperX posts to sidecar and parses forced-aligned response',
        () async {
      final song = Song(
        id: 'wx-1',
        title: 'Midnight City',
        artist: 'M83',
        duration: const Duration(minutes: 4),
        streamUrl: 'https://example.com/audio.mp3',
      );

      final client = MockClient((req) async {
        expect(req.url.toString(), 'http://127.0.0.1:8765/align');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['lyrics'], contains('Waiting in a car'));
        return http.Response(
          jsonEncode({
            'forced_aligned': true,
            'language': 'en',
            'lines': [
              {'start': 4.2, 'end': 7.1, 'text': 'Waiting in a car'},
              {'start': 7.5, 'end': 11.0, 'text': 'Waiting for a ride in the dark'},
            ],
          }),
          200,
        );
      });

      final synced = await WhisperXSyncService.syncWithWhisperX(
        song: song,
        referenceLyrics: 'Waiting in a car\nWaiting for a ride in the dark',
        client: client,
      );

      expect(synced, isNotNull);
      expect(synced!.isSynced, isTrue);
      expect(synced.source, 'whisperx+genius');
      expect(synced.lines.length, 2);
      expect(synced.lines.first.timestamp, const Duration(milliseconds: 4200));
    });
  });

  group('Non-English Song Translation', () {
    setUp(() {
      LyricsTranslationService.clearCacheForTest();
    });

    test('isLikelyNonEnglishText distinguishes English from non-English', () {
      expect(
        LyricsTranslationService.isLikelyNonEnglishText(
            'I love the way you look tonight in the moonlight'),
        isFalse,
      );
      expect(
        LyricsTranslationService.isLikelyNonEnglishText('君の名は希望の光'),
        isTrue,
      );
      expect(
        LyricsTranslationService.isLikelyNonEnglishText(
            'Tú eres mi corazón y la noche de amor'),
        isTrue,
      );
      expect(
        LyricsTranslationService.isLikelyNonEnglishText(
            'Tere bina dil nahi lagda yaar'),
        isTrue,
      );
    });

    test('translateLyrics populates LyricLine.translation for synced non-English song',
        () async {
      final client = MockClient((req) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode([
            [
              ['I am dreaming of the night\n', '夜を夢見ている\n'],
              ['Under the silver moon', '銀の月の下で'],
            ],
            null,
            'ja',
          ])),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      const original = LyricsData(
        isSynced: true,
        source: 'lrclib',
        plainText: '夜を夢見ている\n銀の月の下で',
        lines: [
          LyricLine(timestamp: Duration(seconds: 2), text: '夜を夢見ている'),
          LyricLine(timestamp: Duration(seconds: 6), text: '銀の月の下で'),
        ],
      );

      final translated = await LyricsTranslationService.translateLyrics(
        original,
        songId: 'jp-song-1',
        client: client,
      );

      expect(translated.isSynced, isTrue);
      expect(translated.lines[0].text, '夜を夢見ている');
      expect(translated.lines[0].translation, 'I am dreaming of the night');
      expect(translated.lines[1].translation, 'Under the silver moon');
    });

    test('translateLyrics translates plain-text non-English lyrics', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode([
            [
              ['Hello my heart\n', 'Hola mi corazón\n'],
              ['Under the sky', 'Bajo el cielo'],
            ],
            null,
            'es',
          ]),
          200,
        );
      });

      const original = LyricsData(
        isSynced: false,
        source: 'genius',
        plainText: 'Hola mi corazón\nBajo el cielo',
        lines: [],
      );

      final translated = await LyricsTranslationService.translateLyrics(
        original,
        songId: 'es-song-1',
        client: client,
      );

      expect(translated.isSynced, isFalse);
      expect(translated.translatedPlainText, 'Hello my heart\nUnder the sky');
    });
  });
}
