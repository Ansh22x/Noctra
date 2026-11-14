import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/localization/localization_keys.dart';
import '../../core/utils/localization/localization_scope.dart';
import '../../data/models/catalog_topic.dart';
import '../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../screens/artist_screen.dart';
import 'search/search_artist_card.dart';
import 'search/search_catalog_grid.dart';
import 'search/search_track_tile.dart';
import 'swipeable_song_tile.dart';
import '../../core/theme/noir_theme.dart';

class SearchResultsList extends ConsumerWidget {
  final bool isDark;
  final List<Song> searchResults;
  final bool isSearching;
  final ValueChanged<String>? onGenreTap;
  final List<CatalogTopic>? catalogTopics;
  final bool isLoadingCatalogTopics;

  const SearchResultsList({
    super.key,
    required this.isDark,
    required this.searchResults,
    required this.isSearching,
    this.onGenreTap,
    this.catalogTopics,
    this.isLoadingCatalogTopics = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.noctraTokens;
    final currentSong = ref.watch(currentSongStreamProvider).value;

    if (isSearching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: t.primaryText,
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 14),
            Text(
              context.tr(L10nKeys.buildingCatalog),
              style: TextStyle(
                fontSize: 12,
                color: t.secondaryText,
              ),
            ),
          ],
        ),
      );
    }

    if (searchResults.isEmpty) {
      final activeQuery = ref.watch(searchQueryProvider).trim();
      if (activeQuery.isEmpty) {
        return SearchCatalogGrid(
          isDark: isDark,
          catalogTopics: catalogTopics,
          isLoadingCatalogTopics: isLoadingCatalogTopics,
          onGenreTap: onGenreTap,
        );
      }
      // A real query that found nothing must say so instead of silently
      // showing the browse grid or unrelated trending tracks. Offer a
      // direct route to the artist page: artist pages resolve their own
      // catalog, so names with thin track search still work.
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 40,
                  color: t.tertiaryText),
              const SizedBox(height: 12),
              Text(
                context.tr(L10nKeys.noResultsFor, {'query': activeQuery}),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.secondaryText),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr(L10nKeys.tryShorterName),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: t.tertiaryText),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: Icon(Icons.person_search_rounded,
                    size: 18, color: t.primaryText),
                label: Text(
                  context.tr(L10nKeys.viewArtistPage, {'query': activeQuery}),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.primaryText),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.secondaryText.withAlpha(80)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (c) => ArtistScreen(artistName: activeQuery),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final topArtist = searchResults.first.artist;
    final topArtistImg = searchResults.first.artworkUrl;

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
      itemCount: searchResults.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return SearchArtistCard(
            artistName: topArtist,
            artistImageUrl: topArtistImg,
            isDark: isDark,
          );
        }

        final song = searchResults[i - 1];
        return SwipeableSongTile(
          song: song,
          child: SearchTrackTile(
            song: song,
            isCurrent: currentSong?.id == song.id,
            isDark: isDark,
          ),
        );
      },
    );
  }
}
