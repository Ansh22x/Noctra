import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../data/models/song_model.dart';
import '../../core/utils/noctra_logger.dart';
import '../network/dynamic_template_service.dart';

/// Spotify-powered Recommendation Engine.
/// Replaces all on-device AI/ML models with Spotify's official recommendation algorithms
/// and high-fidelity Spotify-curated catalog radios.
class SpotifyRecommendationService {
  SpotifyRecommendationService._();
  static final SpotifyRecommendationService instance = SpotifyRecommendationService._();

  static const String _tokenUrl =
      'https://open.spotify.com/get_access_token?reason=transport&productType=web_player';
  static const String _recApiUrl = 'https://api.spotify.com/v1/recommendations';

  String? _cachedToken;
  DateTime? _tokenExpiry;

  /// Genre mappings from user/app vibes to Spotify seed genres
  static const Map<String, String> _vibeGenreMap = {
    'Late Night Drive': 'chill,synthwave,electronic',
    'Chill Lo-Fi Session': 'chill,ambient,study',
    'Energetic Workout': 'workout,dance,edm',
    'Acoustic Sunset': 'acoustic,folk,singer-songwriter',
    'Bollywood Classics': 'bollywood,indian',
    'Party & Dance Club': 'dance,party,electronic',
    'Focus & Deep Flow': 'study,ambient,chill',
    'Rock Anthems': 'rock,alternative',
    'Heavy Metal': 'metal,hard-rock',
    'Hip-Hop / Rap': 'hip-hop,rap',
    'R&B & Soul': 'r-n-b,soul',
  };

  /// Fallback Spotify Embed playlist IDs by genre
  static const Map<String, String> _fallbackPlaylistIds = {
    'top': '37i9dQZF1DXcBWIGoYBM5M', // Today's Top Hits
    'global': '37i9dQZEVXbMDoHDwVN2tF', // Top 50 - Global
    'viral': '37i9dQZF1DX2L0iB23Enbq', // Viral 50
    'pop': '37i9dQZF1DWUa8ZRTfalHk', // Pop Rising
    'rap': '37i9dQZF1DX0XUsuxWHRQd', // RapCaviar
    'bollywood': '37i9dQZF1DX0XUfTFmZeM0', // Bollywood Butter
    'chill': '37i9dQZF1DX4WYpdgoIcn6', // Chill Hits
    'rock': '37i9dQZF1DXcF6B6QricJ5', // Rock Classics
    'dance': '37i9dQZF1DX4dyzvuaRJ0n', // Dance Pop
    'indie': '37i9dQZF1DX2Nc3B70tvx0', // Ultimate Indie
  };

  /// Obtains an anonymous Spotify client token for recommendations
  Future<String?> _getSpotifyToken() async {
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedToken;
    }

    try {
      final tRes = await DynamicTemplateService.instance.execute('spotify_token');
      if (tRes is Map<String, dynamic>) {
        final token = tRes['accessToken'] as String?;
        final expiryMs = tRes['accessTokenExpirationTimestampMs'] as num?;
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
          if (expiryMs != null) {
            _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expiryMs.toInt())
                .subtract(const Duration(minutes: 5));
          } else {
            _tokenExpiry = DateTime.now().add(const Duration(minutes: 50));
          }
          return _cachedToken;
        }
      }
    } catch (_) {}

    try {
      final res = await http.get(
        Uri.parse(_tokenUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final token = data['accessToken'] as String?;
        final expiryMs = data['accessTokenExpirationTimestampMs'] as num?;
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
          if (expiryMs != null) {
            _tokenExpiry =
                DateTime.fromMillisecondsSinceEpoch(expiryMs.toInt())
                    .subtract(const Duration(minutes: 5));
          } else {
            _tokenExpiry = DateTime.now().add(const Duration(minutes: 50));
          }
          return _cachedToken;
        }
      }
    } catch (e) {
      NoctraLogger.d('Spotify anonymous token acquisition: $e');
    }
    return null;
  }

  /// Fetches recommendations using Spotify's recommendation algorithms
  Future<List<Song>> getRecommendations({
    List<String>? seedArtists,
    List<String>? seedTracks,
    List<String>? seedGenres,
    int limit = 20,
  }) async {
    final count = limit.clamp(1, 50);

    // 1. Try local native Rust server if running
    try {
      final rustUrl = Uri.parse('http://127.0.0.1:4040/api/spotify/recommendations').replace(
        queryParameters: {
          if (seedArtists != null && seedArtists.isNotEmpty)
            'seed_artists': seedArtists.take(2).join(','),
          if (seedTracks != null && seedTracks.isNotEmpty)
            'seed_tracks': seedTracks.take(2).join(','),
          if (seedGenres != null && seedGenres.isNotEmpty)
            'seed_genres': seedGenres.take(3).join(','),
          'limit': count.toString(),
        },
      );
      final rustResp = await http.get(rustUrl).timeout(const Duration(milliseconds: 1200));
      if (rustResp.statusCode == 200) {
        final data = json.decode(rustResp.body);
        final results = (data['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          return results.map((m) => _parseSpotifyTrackJson(m)).whereType<Song>().toList();
        }
      }
    } catch (_) {}

    // 2. Direct Spotify Recommendation API via DynamicTemplateService / api-anything
    try {
      final token = await _getSpotifyToken();
      if (token != null) {
        final genres = (seedGenres != null && seedGenres.isNotEmpty)
            ? seedGenres.take(3).join(',')
            : 'pop,dance';

        final tRes = await DynamicTemplateService.instance.execute(
          'spotify_recommendations',
          {
            'bearer_token': token,
            'limit': count.toString(),
            'seed_genres': genres,
            'seed_artists': seedArtists?.take(2).join(',') ?? '',
            'seed_tracks': seedTracks?.take(2).join(',') ?? '',
          },
        );

        if (tRes is Map<String, dynamic>) {
          final tracks = (tRes['tracks'] as List?) ?? [];
          final songs = <Song>[];
          for (final t in tracks) {
            final song = _parseSpotifyApiTrack(t);
            if (song != null) songs.add(song);
          }
          if (songs.isNotEmpty) return songs;
        }

        final qParams = <String, String>{
          'limit': count.toString(),
          'seed_genres': genres,
        };
        if (seedArtists != null && seedArtists.isNotEmpty) {
          qParams['seed_artists'] = seedArtists.take(2).join(',');
        }
        if (seedTracks != null && seedTracks.isNotEmpty) {
          qParams['seed_tracks'] = seedTracks.take(2).join(',');
        }

        final uri = Uri.parse(_recApiUrl).replace(queryParameters: qParams);
        final resp = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 5));

        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final tracks = (data['tracks'] as List?) ?? [];
          final songs = <Song>[];
          for (final t in tracks) {
            final song = _parseSpotifyApiTrack(t);
            if (song != null) songs.add(song);
          }
          if (songs.isNotEmpty) {
            return songs;
          }
        }
      }
    } catch (e) {
      NoctraLogger.d('Direct Spotify recommendations query: $e');
    }

    // 3. Fallback to Spotify's curated genre charts
    final fallbackGenre = seedGenres?.firstOrNull?.toLowerCase() ?? 'top';
    final playlistId = _fallbackPlaylistIds[fallbackGenre] ??
        _fallbackPlaylistIds['top']!;
    return fetchSpotifyPlaylistTracks(playlistId, limit: count);
  }

  /// Fetches tracks from a Spotify Embed playlist directly
  Future<List<Song>> fetchSpotifyPlaylistTracks(String playlistId, {int limit = 20}) async {
    try {
      final url = 'https://open.spotify.com/embed/playlist/$playlistId';
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final match = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>')
            .firstMatch(res.body);
        if (match != null) {
          final jsonStr = match.group(1);
          if (jsonStr != null) {
            final data = json.decode(jsonStr) as Map<String, dynamic>;
            final entity = (data['props']?['pageProps']?['state']?['data']?['entity'] ??
                    data['props']?['pageProps']?['data']?['entity'])
                as Map<String, dynamic>?;

            final trackList = (entity?['trackList'] as List?) ?? [];
            final coverSources = (entity?['coverArt']?['sources'] as List?) ?? [];
            final defaultArt = coverSources.isNotEmpty
                ? (coverSources.first['url'] as String? ?? '')
                : '';
            final albumTitle = (entity?['title'] ?? entity?['name'] ?? 'Spotify Playlist') as String;

            final results = <Song>[];
            for (final t in trackList.take(limit)) {
              final title = (t['title'] as String?)?.trim() ?? '';
              final artist = (t['subtitle'] as String?)?.trim() ?? '';
              if (title.isEmpty) continue;

              final uri = (t['uri'] as String?) ?? '';
              final trackId = uri.contains(':') ? uri.split(':').last : (t['uid'] ?? '');
              final durMs = (t['duration'] as num?) ?? 180000;

              results.add(Song(
                id: 'spot_$trackId',
                title: title,
                artist: artist,
                album: albumTitle,
                artworkUrl: defaultArt.isNotEmpty ? defaultArt : null,
                duration: Duration(milliseconds: durMs.toInt()),
                genre: 'Spotify',
              ));
            }
            return results;
          }
        }
      }
    } catch (e) {
      NoctraLogger.d('Failed to fetch Spotify embed playlist: $e');
    }
    return [];
  }

  /// Generates a Spotify Radio track station seeded by a song
  Future<List<Song>> getRadioForTrack(Song seedSong, {int limit = 20}) async {
    return getRecommendations(
      seedArtists: seedSong.artist.isNotEmpty ? [seedSong.artist] : null,
      limit: limit,
    );
  }

  /// Generates recommendations tailored to a folder's content
  Future<List<Song>> getRecommendationsForFolder(List<Song> songs, {int limit = 15}) async {
    if (songs.isEmpty) {
      return getRecommendations(seedGenres: ['pop', 'chill'], limit: limit);
    }
    final artists = songs
        .map((s) => s.artist)
        .where((a) => a.isNotEmpty && a != 'Unknown')
        .toSet()
        .take(2)
        .toList();
    return getRecommendations(
      seedArtists: artists.isNotEmpty ? artists : null,
      limit: limit,
    );
  }

  /// Curates a vibe stream using Spotify's recommendation engine
  Future<List<Song>> getRecommendationsForVibe(String vibe, {int limit = 20}) async {
    final genreSeeds = _vibeGenreMap[vibe] ?? 'pop,dance';
    return getRecommendations(
      seedGenres: genreSeeds.split(','),
      limit: limit,
    );
  }

  Song? _parseSpotifyApiTrack(dynamic json) {
    try {
      final id = json['id'] as String? ?? '';
      final title = json['name'] as String? ?? '';
      final artists = (json['artists'] as List?)
              ?.map((a) => a['name'] as String?)
              .whereType<String>()
              .join(', ') ??
          'Unknown Artist';
      final album = json['album']?['name'] as String? ?? 'Spotify Album';
      final images = (json['album']?['images'] as List?) ?? [];
      final artworkUrl =
          images.isNotEmpty ? (images.first['url'] as String? ?? '') : '';
      final durMs = (json['duration_ms'] as num?) ?? 180000;

      if (title.isEmpty) return null;

      return Song(
        id: 'spot_$id',
        title: title,
        artist: artists,
        album: album,
        artworkUrl: artworkUrl.isNotEmpty ? artworkUrl : null,
        duration: Duration(milliseconds: durMs.toInt()),
        genre: 'Spotify',
      );
    } catch (_) {
      return null;
    }
  }

  Song? _parseSpotifyTrackJson(dynamic map) {
    try {
      return Song(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        artist: map['artist']?.toString() ?? '',
        album: map['album']?.toString() ?? '',
        artworkUrl: map['artworkUrl']?.toString(),
        duration: Duration(seconds: (map['duration'] as num?)?.toInt() ?? 180),
        genre: 'Spotify',
      );
    } catch (_) {
      return null;
    }
  }
}
