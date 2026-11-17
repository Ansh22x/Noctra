import 'dart:async';
import '../../../data/models/song_model.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../services/spotify/spotify_recommendation_service.dart';
import '../domain/recommendation_repository_contract.dart';

/// Infrastructure implementation of [RecommendationRepositoryContract].
/// Bridges recommendation requests directly to Spotify's Recommendation Engine.
class RecommendationRepositoryImpl implements RecommendationRepositoryContract {
  final MusicRepository _musicRepository;

  RecommendationRepositoryImpl({MusicRepository? musicRepository})
      : _musicRepository = musicRepository ?? MusicRepository.instance;

  @override
  Future<List<CuratedCandidate>> getPersonalizedFeed({
    String? vibeKey,
    String? naturalPrompt,
    Song? seedSong,
    int targetCount = 15,
    bool preferDeepCuts = false,
  }) async {
    List<Song> songs;
    if (seedSong != null) {
      songs = await SpotifyRecommendationService.instance
          .getRadioForTrack(seedSong, limit: targetCount);
    } else if (vibeKey != null && vibeKey.isNotEmpty) {
      songs = await SpotifyRecommendationService.instance
          .getRecommendationsForVibe(vibeKey, limit: targetCount);
    } else {
      songs = await SpotifyRecommendationService.instance
          .getRecommendations(limit: targetCount);
    }

    return songs.map((s) => CuratedCandidate(
      id: s.id,
      title: s.title,
      artist: s.artist,
      album: s.album,
      artworkUrl: s.artworkUrl,
      duration: s.duration,
      score: 1.0,
      genre: s.genre,
    )).toList();
  }

  @override
  List<CuratedCandidate> getCuratedByVibe({
    String? vibeKey,
    String? naturalPrompt,
  }) {
    final rawResults = _musicRepository.curateByVibe(
      vibeKey: vibeKey,
      naturalPrompt: naturalPrompt,
    );
    return rawResults.map((m) => CuratedCandidate.fromMap(m)).toList();
  }
}
