import 'dart:math';
import '../../data/models/song_model.dart';
import '../../data/repositories/music_repository.dart';
import '../ytdlp/music_service.dart';

/// Utility to resolve tracks and produce deterministic "remixes" of playlists.
class PlaylistRemixSource {
  PlaylistRemixSource._();

  static const Duration feedTimeout = Duration(seconds: 6);

  static Future<List<Song>> resolveTracks(
    MusicRepository repo, {
    required String vibeKey,
    Future<List<Song>> Function(String vibeKey)? feedFetcher,
  }) {
    return resolveFrom(
      favorites: repo.favorites,
      downloads: repo.downloads,
      localCurator: (vk) => repo
          .curateByVibe(vibeKey: vk)
          .map((e) => e['song'] as Song)
          .where((s) => s.id.isNotEmpty)
          .toList(),
      vibeKey: vibeKey,
      feedFetcher: feedFetcher,
    );
  }

  static Future<List<Song>> resolveRemix(
    MusicRepository repo, {
    required String vibeKey,
    List<String> previousIds = const [],
    int epoch = 0,
    Future<List<Song>> Function(String vibeKey)? feedFetcher,
  }) async {
    final pool = await resolveTracks(repo, vibeKey: vibeKey, feedFetcher: feedFetcher);
    return applyRemixOrder(pool,
        previousIds: previousIds, epoch: epoch, vibeKey: vibeKey);
  }

  static Future<List<Song>> resolveFrom({
    required List<Song> favorites,
    required List<Song> downloads,
    required List<Song> Function(String vibeKey) localCurator,
    required String vibeKey,
    Future<List<Song>> Function(String vibeKey)? feedFetcher,
  }) async {
    if (vibeKey == 'favorites') return favorites;
    if (vibeKey == 'downloads') return downloads;

    try {
      final local = localCurator(vibeKey);
      if (local.isNotEmpty) return local;
    } catch (_) {}

    final fetch = feedFetcher ?? MusicService.fetchVibeFeed;
    List<Song>? feed;
    try {
      feed = await fetch(vibeKey).timeout(feedTimeout);
    } catch (_) {
      feed = null;
    }
    if (feed != null && feed.isNotEmpty) return feed;
    return localCurator(vibeKey);
  }

  static List<Song> applyRemixOrder(
    List<Song> pool, {
    List<String> previousIds = const [],
    int epoch = 0,
    String vibeKey = '',
  }) {
    if (pool.length < 2) return List<Song>.of(pool);
    final seed = (vibeKey.hashCode ^ (epoch * 7919));
    final rnd = Random(seed);
    final fresh = pool.where((s) => !previousIds.contains(s.id)).toList()..shuffle(rnd);
    final repeats = pool.where((s) => previousIds.contains(s.id)).toList()..shuffle(rnd);
    final ordered = <Song>[...fresh, ...repeats];
    if (ordered.isEmpty) return ordered;
    final offset = epoch % ordered.length;
    return [...ordered.sublist(offset), ...ordered.sublist(0, offset)];
  }
}
