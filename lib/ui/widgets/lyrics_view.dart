import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/noir_theme.dart';
import '../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/lyrics_providers.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_translation_service.dart';
import '../../services/lyrics/universal_lyrics_transliteration_engine.dart';
import 'lyrics/lyrics_action_bar.dart';
import 'lyrics/lyrics_plain_text_body.dart';
import 'lyrics/lyrics_script_selector.dart';
import 'lyrics/lyrics_synced_list.dart';

class LyricsView extends ConsumerStatefulWidget {
  final Song song;
  const LyricsView({super.key, required this.song});

  static int findActiveIndex(List<LyricLine> lines, Duration pos) {
    if (lines.isEmpty || pos < lines.first.timestamp) return -1;
    for (int i = lines.length - 1; i >= 0; i--) {
      if (lines[i].timestamp <= pos) return i;
    }
    return -1;
  }

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  late Future<LyricsData> _lyricsFuture;
  LyricsData? _overrideData;
  int _lastActiveIndex = -1, _lastScrolledIndex = -1;
  int _lyricsGeneration = 0, _scrollGeneration = 0;
  bool _userIsScrolling = false, _isTranslating = false, _isSyncingWX = false;
  bool _showTranslation = true;
  Timer? _resumeAutoScrollTimer;
  StreamSubscription<Duration>? _positionSub;
  String _selectedScript = 'original';
  List<LyricLine> _cachedLines = [];
  bool _isSynced = false;
  String _plainText = '';

  @override
  void initState() {
    super.initState();
    _showTranslation = ref.read(autoTranslateLyricsProvider);
    _loadLyrics();
    _positionSub =
        ref.read(audioPlayerServiceProvider).player.positionStream.listen((p) {
      if (!mounted || !_isSynced || _cachedLines.isEmpty) return;
      final idx = LyricsView.findActiveIndex(_cachedLines, p);
      if (idx == _lastActiveIndex) return;
      setState(() => _lastActiveIndex = idx);
      if (!_userIsScrolling && idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToIndex(idx);
        });
      }
    });
  }

  void _loadLyrics() {
    final pref = ref.read(lyricsPreferenceProvider);
    final prefKey = pref.toLowerCase();
    final prefScript = prefKey.contains('romanized')
        ? 'roman'
        : (prefKey.contains('devanagari') ? 'devanagari' : 'original');
    final gen = ++_lyricsGeneration;
    final songId = widget.song.id;
    _overrideData = null;
    _lyricsFuture = LyricsService.fetchLyrics(
      widget.song,
      preference: pref,
      autoTranslate: ref.read(autoTranslateLyricsProvider),
      enableWhisperX: ref.read(whisperxEnabledProvider),
      whisperxEndpoint: ref.read(whisperxEndpointProvider),
      geniusApiToken: ref.read(geniusApiTokenProvider),
    );
    _lyricsFuture.then((data) => _applyLoadedData(data, gen, songId, prefScript));
  }

  void _applyLoadedData(LyricsData data, int gen, String songId, String prefScript) {
    if (!mounted || gen != _lyricsGeneration || widget.song.id != songId) return;
    final pos = ref.read(audioPlayerServiceProvider).player.position;
    final activeIdx = data.isSynced && data.lines.isNotEmpty
        ? LyricsView.findActiveIndex(data.lines, pos)
        : -1;
    setState(() {
      _selectedScript = _selectedScript != 'original' ? _selectedScript : prefScript;
      _cachedLines = data.lines;
      _isSynced = data.isSynced;
      _plainText = data.plainText;
      _lineKeys.clear();
      _lastActiveIndex = activeIdx;
    });
    if (data.isSynced && activeIdx >= 0 && !_userIsScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && gen == _lyricsGeneration) _scrollToIndex(activeIdx);
      });
    }
  }

  Future<void> _toggleTranslation(LyricsData current) async {
    if (_showTranslation) { setState(() => _showTranslation = false); return; }
    setState(() { _showTranslation = true; _isTranslating = true; });
    final translated = await LyricsTranslationService.translateLyrics(
      current, songId: widget.song.id, targetLang: 'en', force: true,
    );
    if (!mounted) return;
    setState(() {
      _isTranslating = false;
      _overrideData = translated;
      if (translated.isSynced) _cachedLines = translated.lines;
    });
  }

  Future<void> _triggerWhisperXSync(LyricsData current) async {
    if (_isSyncingWX) return;
    setState(() => _isSyncingWX = true);
    final synced = await LyricsService.syncWithWhisperXGenius(
      widget.song,
      existingPlainLyrics: current.plainText,
      autoTranslate: _showTranslation,
      whisperxEndpoint: ref.read(whisperxEndpointProvider),
      geniusApiToken: ref.read(geniusApiTokenProvider),
    );
    if (!mounted) return;
    setState(() {
      _isSyncingWX = false;
      if (synced != null) {
        _overrideData = synced;
        _cachedLines = synced.lines;
        _isSynced = synced.isSynced;
        _plainText = synced.plainText;
        _lineKeys.clear();
      }
    });
    final msg = synced != null
        ? 'Synced lyrics via ${synced.source.toUpperCase()}'
        : 'WhisperX sidecar unreachable (${ref.read(whisperxEndpointProvider)}). Run tool/whisperx_server.py or set URL in Settings.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _resetStateForNewSong() {
    _lyricsGeneration++;
    _scrollGeneration++;
    _lastActiveIndex = -1;
    _lastScrolledIndex = -1;
    _userIsScrolling = false;
    _resumeAutoScrollTimer?.cancel();
    _lineKeys.clear();
    _cachedLines = [];
    _isSynced = false;
    _plainText = '';
    _overrideData = null;
    _showTranslation = ref.read(autoTranslateLyricsProvider);
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id == widget.song.id) return;
    _resetStateForNewSong();
    _loadLyrics();
  }

  void _scrollToIndex(int index, {bool isRetry = false}) {
    if (!mounted || !_scrollController.hasClients || _userIsScrolling) return;
    if (index < 0 || index >= _cachedLines.length) return;
    if (index == _lastScrolledIndex && !isRetry) return;
    final targetGen = ++_scrollGeneration;
    _lastScrolledIndex = index;
    final ctx = _lineKeys[index]?.currentContext;
    if (ctx == null || !ctx.mounted) {
      if (!isRetry) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && targetGen == _scrollGeneration) _scrollToIndex(index, isRetry: true);
        });
      }
      return;
    }
    Scrollable.ensureVisible(ctx, alignment: 0.40,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _resumeAutoScroll() {
    _resumeAutoScrollTimer?.cancel();
    if (!mounted) return;
    final pos = ref.read(audioPlayerServiceProvider).player.position;
    final activeIdx = LyricsView.findActiveIndex(_cachedLines, pos);
    setState(() {
      _userIsScrolling = false;
      if (activeIdx >= 0) _lastActiveIndex = activeIdx;
    });
    _lastScrolledIndex = -1;
    _scrollToIndex(_lastActiveIndex >= 0 ? _lastActiveIndex : 0);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _resumeAutoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(lyricsPreferenceProvider, (_, __) {
      if (mounted) _loadLyrics();
    });
    final isDark = ref.watch(themeModeProvider).isDark;

    return FutureBuilder<LyricsData>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _cachedLines.isEmpty &&
            _overrideData == null) {
          return LyricsLoadingState(isDark: isDark);
        }
        final rawData = _overrideData ?? snapshot.data ?? LyricsData.empty();
        final isEmpty = rawData.plainText == LyricsData.empty().plainText &&
            rawData.lines.isEmpty;
        final options = isEmpty
            ? const <ScriptOption>[]
            : UniversalLyricsTransliterationEngine.getAvailableScriptOptions(rawData);
        var data = rawData;
        try {
          data = UniversalLyricsTransliterationEngine.transliterateLyrics(
              rawData, _selectedScript);
        } catch (_) {}

        final rawLines = data.isSynced ? data.lines : _cachedLines;
        final displayLines = _showTranslation
            ? rawLines
            : rawLines.map((l) => LyricLine(timestamp: l.timestamp, text: l.text)).toList();
        final isSynced = data.isSynced || _isSynced;
        final canTranslate = LyricsTranslationService.isLikelyNonEnglish(rawData) ||
            rawData.translatedPlainText != null ||
            rawData.lines.any((l) => l.translation != null);
        return Stack(
          children: [
            Positioned.fill(
              child: isSynced && displayLines.isNotEmpty
                  ? NotificationListener<ScrollNotification>(
                      onNotification: _handleScrollNotification,
                      child: LyricsSyncedList(
                        scrollController: _scrollController,
                        displayLines: displayLines,
                        activeIndex: _lastActiveIndex,
                        isDark: isDark,
                        lineKeys: _lineKeys,
                        onLineTap: (line, index) {
                          ref.read(audioPlayerServiceProvider).seek(line.timestamp);
                          _resumeAutoScrollTimer?.cancel();
                          setState(() => _userIsScrolling = false);
                          _scrollToIndex(index);
                        },
                      ),
                    )
                  : LyricsPlainTextBody(
                      text: data.plainText.isNotEmpty ? data.plainText : _plainText,
                      translatedText: _showTranslation ? data.translatedPlainText : null,
                      isDark: isDark,
                    ),
            ),
            LyricsActionBar(
              options: options,
              selectedScript: _selectedScript,
              isDark: isDark,
              showTranslation: _showTranslation,
              canTranslate: canTranslate,
              isTranslating: _isTranslating,
              isSyncingWhisperX: _isSyncingWX,
              sourceLabel: rawData.source,
              onSelectScript: (c) {
                if (_selectedScript != c) setState(() { _selectedScript = c; _lineKeys.clear(); });
              },
              onToggleTranslation: () => _toggleTranslation(rawData),
              onWhisperXSync: () => _triggerWhisperXSync(rawData),
            ),
            if (_userIsScrolling && isSynced && displayLines.isNotEmpty)
              LyricsSyncFloatingButton(isDark: isDark, onTap: _resumeAutoScroll),
          ],
        );
      },
    );
  }

  bool _handleScrollNotification(ScrollNotification n) {
    if ((n is ScrollStartNotification && n.dragDetails != null) ||
        (n is UserScrollNotification && n.direction != ScrollDirection.idle)) {
      if (!_userIsScrolling) setState(() => _userIsScrolling = true);
      _resumeAutoScrollTimer?.cancel();
    } else if (n is ScrollEndNotification) {
      _resumeAutoScrollTimer?.cancel();
      _resumeAutoScrollTimer =
          Timer(const Duration(milliseconds: 3500), _resumeAutoScroll);
    }
    return false;
  }
}
