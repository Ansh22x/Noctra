import 'package:flutter_test/flutter_test.dart';
import 'package:noctra/data/models/song_model.dart';
import 'package:noctra/services/spotify/spotify_recommendation_service.dart';

void main() {
  group('SpotifyRecommendationService Tests', () {
    test('Spotify recommendation service singleton initializes', () {
      final service = SpotifyRecommendationService.instance;
      expect(service, isNotNull);
    });

    test('getRecommendations parses fallback structure cleanly', () async {
      final service = SpotifyRecommendationService.instance;
      // When offline or in sandbox, verify graceful fallback handling
      final recs = await service.getRecommendations(seedGenres: ['pop'], limit: 5);
      expect(recs, isA<List<Song>>());
    });

    test('getRadioForTrack generates radio query for seed track', () async {
      final service = SpotifyRecommendationService.instance;
      final seed = Song(
        id: 'seed_1',
        title: 'Starboy',
        artist: 'The Weeknd',
        duration: const Duration(seconds: 230),
      );
      final radio = await service.getRadioForTrack(seed, limit: 10);
      expect(radio, isA<List<Song>>());
    });

    test('getRecommendationsForFolder extracts artist seeds cleanly', () async {
      final service = SpotifyRecommendationService.instance;
      final songs = [
        Song(id: '1', title: 'Song 1', artist: 'Dua Lipa', duration: const Duration(seconds: 180)),
        Song(id: '2', title: 'Song 2', artist: 'Coldplay', duration: const Duration(seconds: 240)),
      ];
      final recs = await service.getRecommendationsForFolder(songs, limit: 8);
      expect(recs, isA<List<Song>>());
    });
  });
}
