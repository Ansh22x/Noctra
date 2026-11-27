import 'package:flutter/material.dart';
import '../../../core/theme/noir_theme.dart';

/// Static, non-synced lyrics rendered as centered plain text, with optional
/// line-by-line translation underneath for non-English songs.
class LyricsPlainTextBody extends StatelessWidget {
  final String text;
  final String? translatedText;
  final bool isDark;

  const LyricsPlainTextBody({
    super.key,
    required this.text,
    this.translatedText,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.noctraTokens;
    final hasTranslation =
        translatedText != null && translatedText!.trim().isNotEmpty;

    if (!hasTranslation) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            height: 1.8,
            color: t.secondaryText,
          ),
        ),
      );
    }

    final origLines = text.split('\n');
    final trLines = translatedText!.split('\n');
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
      child: Column(
        children: List.generate(origLines.length, (i) {
          final orig = origLines[i].trim();
          final tr = i < trLines.length ? trLines[i].trim() : '';
          if (orig.isEmpty) return const SizedBox(height: 12);
          final showTr =
              tr.isNotEmpty && tr.toLowerCase() != orig.toLowerCase();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                Text(
                  orig,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                    color: t.primaryText,
                  ),
                ),
                if (showTr) ...[
                  const SizedBox(height: 2),
                  Text(
                    tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                      color: t.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Centered loading indicator shown while lyrics are being fetched.
class LyricsLoadingState extends StatelessWidget {
  final bool isDark;

  const LyricsLoadingState({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final t = context.noctraTokens;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(strokeWidth: 2, color: t.secondaryText),
          const SizedBox(height: 14),
          Text(
            'Syncing Studio Lyrics...',
            style: TextStyle(fontSize: 12, color: t.secondaryText),
          ),
        ],
      ),
    );
  }
}
