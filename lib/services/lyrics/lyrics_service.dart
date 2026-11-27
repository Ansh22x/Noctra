import '../../core/utils/playback_settings_store.dart';
import '../../data/models/song_model.dart';
import 'lyrics_matcher.dart';
import 'lyrics_translation_service.dart';
import 'parts/lyrics_genius_provider.dart';
import 'parts/lyrics_innertube_provider.dart';
import 'parts/lyrics_lrclib_provider.dart';
import 'parts/lyrics_provider_fallback.dart';
import 'parts/lyrics_whisperx_provider.dart';

class LyricLine {
  final Duration timestamp;
  final String text;
  final String? translation;

  const LyricLine({
    required this.timestamp,
    required this.text,
    this.translation,
  });
}

class LyricsData {
  final bool isSynced;
  final List<LyricLine> lines;
  final String plainText;
  final String source;
  final String? translatedPlainText;

  const LyricsData({
    required this.isSynced,
    required this.lines,
    required this.plainText,
    this.source = '',
    this.translatedPlainText,
  });

  factory LyricsData.empty() => const LyricsData(
        isSynced: false,
        lines: [],
        plainText:
            'No lyrics found for this track.\nEnjoy the pure acoustic flow.',
      );
}

class LyricsService {
  static final Map<String, LyricsData> _cache = {};
  static const int _maxCacheSize = 100;

  static void _setCache(String key, LyricsData data) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = data;
  }

  static Future<LyricsData> fetchLyrics(
    Song song, {
    String preference = 'English / Global',
    bool? autoTranslate,
    bool? enableWhisperX,
    String? whisperxEndpoint,
    String? geniusApiToken,
  }) async {
    final store = PlaybackSettingsStore.instance;
    final useTranslate = autoTranslate ?? store.autoTranslateNonEnglish;
    final useWhisperX = enableWhisperX ?? store.whisperxEnabled;
    final wxEndpoint = whisperxEndpoint ?? store.whisperxEndpoint;
    final gToken = geniusApiToken ?? store.geniusApiToken;

    final cacheKey = '${song.id}_${preference}_tr$useTranslate';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    final cleanTitle = LyricsMatcher.sanitizeTitle(song.title);
    final primaryArtist = LyricsMatcher.extractPrimaryArtist(song.artist);
    final preferenceKey = preference.toLowerCase();
    final bool preferHindi =
        preferenceKey.contains('romanized') || preferenceKey == 'hi';

    Future<LyricsData> finalize(LyricsData raw) async {
      final result = useTranslate
          ? await LyricsTranslationService.translateLyrics(
              raw,
              songId: song.id,
              targetLang: 'en',
            )
          : raw;
      _setCache(cacheKey, result);
      return result;
    }

    // Tier 1 & 2: LRCLIB (Direct Match + Fuzzy Multi-Query Search)
    final lrclibResult = await LyricsLrclibProvider.searchLrclibDirect(
      song: song,
      cleanTitle: cleanTitle,
      primaryArtist: primaryArtist,
      preferHindi: preferHindi,
    );
    if (lrclibResult != null && lrclibResult.isSynced) {
      return finalize(lrclibResult);
    }

    // Tier 3: Musixmatch (via broad LRCLIB search)
    final mmLyrics = await LyricsProviderFallback.fetchMusixmatchLyrics(
      cleanTitle,
      primaryArtist,
      song.title,
    );
    if (mmLyrics != null && mmLyrics.isSynced) {
      return finalize(mmLyrics);
    }

    // Tier 4: YouTube Music / InnerTube Musixmatch Extractor
    final ytLyrics = await LyricsInnertubeProvider.fetchInnerTubeLyrics(
      song.id,
      cleanTitle,
      primaryArtist,
    );
    if (ytLyrics != null && ytLyrics.isSynced) {
      return finalize(ytLyrics);
    }

    // Tier 5: Genius Lyrics + WhisperX Forced Alignment for high-accuracy sync
    final geniusLyrics = await LyricsGeniusProvider.fetchGeniusLyrics(
      song.title,
      cleanTitle,
      primaryArtist,
      apiToken: gToken,
    );
    if (geniusLyrics != null) {
      if (useWhisperX) {
        final wxSynced = await WhisperXSyncService.syncWithWhisperX(
          song: song,
          referenceLyrics: geniusLyrics.plainText,
          endpointUrl: wxEndpoint,
          sourceLabel: 'whisperx+genius',
        );
        if (wxSynced != null) {
          return finalize(wxSynced);
        }
      }
      return finalize(geniusLyrics);
    }

    // Tier 6: Unsynced fallbacks from earlier tiers + JioSaavn
    final plainFallback = lrclibResult ??
        mmLyrics ??
        ytLyrics ??
        await LyricsProviderFallback.fetchJioSaavnLyrics(
          song.title,
          cleanTitle,
          primaryArtist,
        );
    if (plainFallback != null) {
      if (useWhisperX && !plainFallback.isSynced) {
        final wxSynced = await WhisperXSyncService.syncWithWhisperX(
          song: song,
          referenceLyrics: plainFallback.plainText,
          endpointUrl: wxEndpoint,
          sourceLabel: 'whisperx',
        );
        if (wxSynced != null) {
          return finalize(wxSynced);
        }
      }
      return finalize(plainFallback);
    }

    // Tier 7: Last resort — LRCLIB search with artist+title combination
    final fallbackLyrics = await LyricsLrclibProvider.searchLrclibFallback(
      song: song,
      cleanTitle: cleanTitle,
      primaryArtist: primaryArtist,
    );
    if (fallbackLyrics != null) {
      return finalize(fallbackLyrics);
    }

    // Tier 8: Pure WhisperX audio transcription+alignment when no text lyrics exist
    if (useWhisperX) {
      final wxDirect = await WhisperXSyncService.syncWithWhisperX(
        song: song,
        endpointUrl: wxEndpoint,
        sourceLabel: 'whisperx',
      );
      if (wxDirect != null) {
        return finalize(wxDirect);
      }
    }

    return LyricsData.empty();
  }

  /// On-demand WhisperX + Genius forced alignment for any song (even if a
  /// synced LRC already existed, allowing higher-accuracy re-sync).
  static Future<LyricsData?> syncWithWhisperXGenius(
    Song song, {
    String? existingPlainLyrics,
    bool autoTranslate = true,
    String? whisperxEndpoint,
    String? geniusApiToken,
  }) async {
    final store = PlaybackSettingsStore.instance;
    final cleanTitle = LyricsMatcher.sanitizeTitle(song.title);
    final primaryArtist = LyricsMatcher.extractPrimaryArtist(song.artist);
    final genius = await LyricsGeniusProvider.fetchGeniusLyrics(
      song.title,
      cleanTitle,
      primaryArtist,
      apiToken: geniusApiToken ?? store.geniusApiToken,
    );
    final refText = genius?.plainText ?? existingPlainLyrics;
    final synced = await WhisperXSyncService.syncWithWhisperX(
      song: song,
      referenceLyrics: refText,
      endpointUrl: whisperxEndpoint ?? store.whisperxEndpoint,
      sourceLabel: genius != null ? 'whisperx+genius' : 'whisperx',
    );
    if (synced == null) return null;

    return autoTranslate
        ? await LyricsTranslationService.translateLyrics(
            synced,
            songId: song.id,
            targetLang: 'en',
          )
        : synced;
  }

  // ── Test-only public wrappers for private helpers ──
  static bool titlesMatchForTest(String a, String b) =>
      LyricsMatcher.titlesMatch(a, b);
  static bool hasNonLatinScriptForTest(String text) =>
      LyricsMatcher.hasNonLatinScript(text);
  static List<LyricLine> parseLrcForTest(String lrc) =>
      LyricsMatcher.parseLrc(lrc);
  static String sanitizeTitleForTest(String title) =>
      LyricsMatcher.sanitizeTitle(title);
  static void setCacheForTest(String key, LyricsData data) =>
      _setCache(key, data);
  static void setCacheForSong(Song song, LyricsData data) {
    final store = PlaybackSettingsStore.instance;
    final tr = store.autoTranslateNonEnglish;
    _setCache('${song.id}_English / Global (Standard)_tr$tr', data);
    _setCache('${song.id}_Romanized Hindi/Punjabi_tr$tr', data);
    _setCache('${song.id}_Devanagari Hindi_tr$tr', data);
    _setCache('${song.id}_English / Global (Standard)', data);
    _setCache('${song.id}_Romanized Hindi/Punjabi', data);
    _setCache('${song.id}_Devanagari Hindi', data);
  }

  static void clearCacheForTest() => _cache.clear();
}
