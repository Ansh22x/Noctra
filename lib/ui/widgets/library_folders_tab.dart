import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/localization/localization_keys.dart';
import '../../core/utils/localization/localization_scope.dart';
import '../../data/models/song_model.dart';
import '../../data/repositories/music_repository.dart';
import '../../shared/widgets/glass_card.dart';
import '../../core/theme/noir_theme.dart';
import '../screens/migration/url_import_sheet.dart';
import 'library/folder_artwork_cover.dart';
import 'library/folder_delete_sheet.dart';
import 'library/folder_detail_view.dart';
import 'library/local_scan_card.dart';
import 'listening_insights_sheet.dart';

class LibraryFoldersTab extends ConsumerStatefulWidget {
  final bool isDark;
  final MusicRepository repo;
  final Map<String, List<Song>> customFolders;
  final List<Song> allSongs;

  @visibleForTesting
  static bool debugDisableDebounce = false;

  const LibraryFoldersTab({
    super.key,
    required this.isDark,
    required this.repo,
    required this.customFolders,
    required this.allSongs,
  });

  @override
  ConsumerState<LibraryFoldersTab> createState() => _LibraryFoldersTabState();
}

class _LibraryFoldersTabState extends ConsumerState<LibraryFoldersTab>
    with AutomaticKeepAliveClientMixin {
  DateTime? _lastOpenTime;
  bool _isCreatingFolder = false;
  final TextEditingController _folderNameCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _folderNameCtrl.dispose();
    super.dispose();
  }

  void _openFolder(String folderName, List<Song> folderSongs) {
    final now = DateTime.now();
    if (!LibraryFoldersTab.debugDisableDebounce &&
        _lastOpenTime != null &&
        now.difference(_lastOpenTime!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastOpenTime = now;
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderDetailView(
          isDark: widget.isDark,
          repo: widget.repo,
          folderName: folderName,
          songs: folderSongs,
        ),
      ),
    );
  }

  void _submitCreateFolder() {
    final name = _folderNameCtrl.text.trim();
    if (name.isNotEmpty) {
      widget.repo.createFolder(name);
      _folderNameCtrl.clear();
      setState(() => _isCreatingFolder = false);
    }
  }

  void _confirmDeleteFolder(String folderName) {
    if (folderName == 'Downloads' || folderName == 'Favorites') return;
    showFolderDeleteSheet(
      context,
      isDark: widget.isDark,
      folderName: folderName,
      onDelete: () => widget.repo.deleteFolder(folderName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.noctraTokens;
    super.build(context);

    // Fixed folders: Downloads (fixed for all downloaded songs) and Favorites,
    // followed by user-created & imported playlist folders
    final customFolderNames = widget.repo.customFolders.keys.toList();
    final folderNames = <String>[
      'Downloads',
      'Favorites',
      ...customFolderNames,
    ];

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth >= 1100
        ? 4
        : (screenWidth >= 720 ? 3 : 2);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Action Bar: Create Folder, Import Playlist Link, Insights
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: !_isCreatingFolder
                ? Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isCreatingFolder = true),
                              child: GlassCard(
                                radius: 16,
                                isHighlighted: true,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: t.primaryText,
                                      ),
                                      child: Icon(Icons.create_new_folder_outlined,
                                          size: 18, color: t.canvas),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '+ ${context.tr(L10nKeys.createFolder)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: t.primaryText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => UrlImportSheet.show(context, widget.isDark),
                            child: GlassCard(
                              radius: 16,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF00E5FF).withValues(alpha: 0.18),
                                    ),
                                    child: const Icon(
                                      Icons.link_rounded,
                                      size: 18,
                                      color: Color(0xFF00E5FF),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Import Link',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: t.primaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => ListeningInsightsSheet.show(context),
                            child: GlassCard(
                              radius: 16,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: Icon(
                                Icons.analytics_outlined,
                                size: 20,
                                color: t.primaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LocalScanCard(isDark: widget.isDark, repo: widget.repo),
                    ],
                  )
                : GlassCard(
                    radius: 16,
                    isHighlighted: true,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(L10nKeys.createFolder),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: t.primaryText,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _folderNameCtrl,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: context.tr(L10nKeys.folderNameHint),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: TextStyle(fontSize: 13.5, color: t.primaryText),
                                onSubmitted: (_) => _submitCreateFolder(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: context.tr(L10nKeys.cancel),
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () => setState(() {
                                _folderNameCtrl.clear();
                                _isCreatingFolder = false;
                              }),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.primaryText,
                                foregroundColor: t.canvas,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _submitCreateFolder,
                              child: Text(
                                context.tr(L10nKeys.create),
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // Big Artwork Folder Grid
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final folderName = folderNames[i];
                final List<Song> folderSongs;
                final String subtitle;
                final bool isFixed = folderName == 'Downloads' || folderName == 'Favorites';

                if (folderName == 'Downloads') {
                  folderSongs = widget.repo.downloads;
                  subtitle = '${folderSongs.length} tracks • Offline Vault';
                } else if (folderName == 'Favorites') {
                  folderSongs = widget.repo.favorites;
                  subtitle = '${folderSongs.length} tracks • Favorites';
                } else {
                  folderSongs = widget.repo.customFolders[folderName] ?? [];
                  subtitle = '${folderSongs.length} tracks';
                }

                return GestureDetector(
                  onTap: () => _openFolder(folderName, folderSongs),
                  onLongPress: !isFixed
                      ? () => _confirmDeleteFolder(folderName)
                      : null,
                  child: GlassCard(
                    radius: 18,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Big Artwork Cover
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Center(
                                child: FolderArtworkCover(
                                  folderName: folderName,
                                  songs: folderSongs,
                                  size: constraints.biggest.shortestSide,
                                  radius: 14,
                                  isDark: widget.isDark,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Folder Name
                        Row(
                          children: [
                            if (folderName == 'Downloads') ...[
                              const Icon(Icons.download_for_offline_rounded,
                                  size: 15, color: Color(0xFF00E5FF)),
                              const SizedBox(width: 4),
                            ] else if (folderName == 'Favorites') ...[
                              const Icon(Icons.favorite_rounded,
                                  size: 15, color: Color(0xFFFF4081)),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                folderName == 'Favorites'
                                    ? context.tr(L10nKeys.favorites)
                                    : (folderName == 'Downloads' ? 'Downloads' : folderName),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: t.primaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Subtitle
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: t.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: folderNames.length,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }
}
