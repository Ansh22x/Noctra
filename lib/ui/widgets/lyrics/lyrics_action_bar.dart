import 'package:flutter/material.dart';
import '../../../core/theme/noir_theme.dart';
import '../../../services/lyrics/universal_lyrics_transliteration_engine.dart';

/// Top floating bar in [LyricsView] housing script selection chips,
/// non-English translation toggle, and WhisperX+Genius re-sync action.
class LyricsActionBar extends StatelessWidget {
  final List<ScriptOption> options;
  final String selectedScript;
  final bool isDark;
  final bool showTranslation;
  final bool canTranslate;
  final bool isTranslating;
  final bool isSyncingWhisperX;
  final String sourceLabel;
  final ValueChanged<String> onSelectScript;
  final VoidCallback onToggleTranslation;
  final VoidCallback onWhisperXSync;

  const LyricsActionBar({
    super.key,
    required this.options,
    required this.selectedScript,
    required this.isDark,
    required this.showTranslation,
    required this.canTranslate,
    required this.isTranslating,
    required this.isSyncingWhisperX,
    required this.sourceLabel,
    required this.onSelectScript,
    required this.onToggleTranslation,
    required this.onWhisperXSync,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.noctraTokens;
    return Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            if (options.length > 1)
              ...options.map((opt) => _chip(
                    context: context,
                    label: opt.label,
                    selected: selectedScript == opt.code,
                    onTap: () => onSelectScript(opt.code),
                  )),
            if (canTranslate)
              _chip(
                context: context,
                label: isTranslating
                    ? 'Translating…'
                    : (showTranslation ? 'EN Translation ✓' : 'Translate'),
                selected: showTranslation,
                icon: Icons.translate_rounded,
                onTap: isTranslating ? null : onToggleTranslation,
              ),
            _chip(
              context: context,
              label: isSyncingWhisperX ? 'Syncing…' : 'WhisperX Sync',
              selected: sourceLabel.contains('whisperx'),
              icon: Icons.graphic_eq_rounded,
              onTap: isSyncingWhisperX ? null : onWhisperXSync,
            ),
            if (sourceLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0x1FFFFFFF)
                        : const Color(0x14000000),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      sourceLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: t.tertiaryText,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required BuildContext context,
    required String label,
    required bool selected,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final t = context.noctraTokens;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? Colors.white.withValues(alpha: 0.90) : Colors.black.withValues(alpha: 0.85))
                : (isDark
                    ? const Color(0x33FFFFFF)
                    : const Color(0x1F000000)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: selected
                      ? (isDark ? Colors.black : Colors.white)
                      : t.secondaryText,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? (isDark ? Colors.black : Colors.white)
                      : t.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
