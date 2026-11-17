import 'package:flutter/material.dart';
import '../../../data/models/song_model.dart';
import '../../../core/theme/noir_theme.dart';

/// Renders a prominent, high-resolution artwork cover for library folders and playlists.
/// - If 4 or more songs exist: generates a Spotify-style 2x2 artwork mosaic.
/// - If 1-3 songs exist: displays the primary track's hero artwork.
/// - If empty: renders a rich glassmorphic themed placeholder with symbolic branding.
class FolderArtworkCover extends StatelessWidget {
  final String folderName;
  final List<Song> songs;
  final double size;
  final double radius;
  final bool isDark;

  const FolderArtworkCover({
    super.key,
    required this.folderName,
    required this.songs,
    this.size = 140,
    this.radius = 16,
    required this.isDark,
  });

  bool get _isDownloads => folderName == 'Downloads';
  bool get _isFavorites => folderName == 'Favorites';

  @override
  Widget build(BuildContext context) {
    final t = context.noctraTokens;
    final artworks = songs
        .map((s) => s.artworkUrl)
        .where((u) => u != null && u.isNotEmpty)
        .cast<String>()
        .take(4)
        .toList();

    Widget content;
    if (artworks.length >= 4) {
      content = _build2x2Mosaic(artworks);
    } else if (artworks.isNotEmpty) {
      content = _buildSingleArtwork(artworks.first);
    } else {
      content = _buildEmptyPlaceholder(t);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            // Subtle specular glass border overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: t.subtleBorder,
                  width: 1.0,
                ),
              ),
            ),
            // Corner badge indicator for Downloads and Favorites
            if (_isDownloads)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.download_done_rounded,
                    color: Color(0xFF00E5FF),
                    size: 14,
                  ),
                ),
              )
            else if (_isFavorites)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF4081).withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFFF4081),
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _build2x2Mosaic(List<String> urls) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _singleQuad(urls[0])),
              Expanded(child: _singleQuad(urls[1])),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _singleQuad(urls[2])),
              Expanded(child: _singleQuad(urls[3])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _singleQuad(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFF161620),
        child: const Icon(Icons.music_note_rounded, size: 18, color: Colors.white24),
      ),
    );
  }

  Widget _buildSingleArtwork(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => _buildFallbackBg(),
    );
  }

  Widget _buildEmptyPlaceholder(NoctraThemeTokens t) {
    final IconData icon;
    final Color iconColor;
    final List<Color> gradientColors;

    if (_isDownloads) {
      icon = Icons.download_rounded;
      iconColor = const Color(0xFF00E5FF);
      gradientColors = [
        const Color(0xFF003844),
        const Color(0xFF0B1726),
      ];
    } else if (_isFavorites) {
      icon = Icons.favorite_rounded;
      iconColor = const Color(0xFFFF4081);
      gradientColors = [
        const Color(0xFF4A1024),
        const Color(0xFF1E0A14),
      ];
    } else {
      icon = Icons.folder_rounded;
      iconColor = t.secondaryText;
      gradientColors = [
        const Color(0xFF1E1E28),
        const Color(0xFF0E0E14),
      ];
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.36,
          color: iconColor,
        ),
      ),
    );
  }

  Widget _buildFallbackBg() {
    return Container(
      color: const Color(0xFF161620),
      child: const Center(
        child: Icon(Icons.music_note_rounded, size: 36, color: Colors.white24),
      ),
    );
  }
}
