import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/noir_theme.dart';
import '../../../core/utils/playback_settings_store.dart';
import '../../../providers/lyrics_providers.dart';
import '../../../shared/widgets/glass_card.dart';

class WhisperXGeniusSettingsCard extends ConsumerWidget {
  const WhisperXGeniusSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.noctraTokens;
    final whisperxEnabled = ref.watch(whisperxEnabledProvider);
    final whisperxEndpoint = ref.watch(whisperxEndpointProvider);
    final geniusToken = ref.watch(geniusApiTokenProvider);
    final autoTranslate = ref.watch(autoTranslateLyricsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHISPERX + GENIUS & TRANSLATION',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: t.secondaryText,
          ),
        ),
        const SizedBox(height: 8),
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              _toggleRow(
                context: context,
                title: 'Auto-Translate Non-English Songs',
                subtitle: 'Show English translation under foreign lyrics',
                value: autoTranslate,
                onChanged: (v) {
                  ref.read(autoTranslateLyricsProvider.notifier).state = v;
                  PlaybackSettingsStore.instance
                      .save(autoTranslateNonEnglish: v);
                },
              ),
              const Divider(height: 4),
              _toggleRow(
                context: context,
                title: 'WhisperX + Genius Sync',
                subtitle: 'Forced-align Genius lyrics to audio timestamps',
                value: whisperxEnabled,
                onChanged: (v) {
                  ref.read(whisperxEnabledProvider.notifier).state = v;
                  PlaybackSettingsStore.instance.save(whisperxEnabled: v);
                },
              ),
              const Divider(height: 4),
              _editableRow(
                context: context,
                title: 'WhisperX Sidecar URL',
                value: whisperxEndpoint,
                hint: 'http://127.0.0.1:8765',
                onSave: (val) {
                  ref.read(whisperxEndpointProvider.notifier).state = val;
                  PlaybackSettingsStore.instance.save(whisperxEndpoint: val);
                },
              ),
              const Divider(height: 4),
              _editableRow(
                context: context,
                title: 'Genius API Token (Optional)',
                value: geniusToken.isEmpty ? 'Zero-Key Public' : 'Configured',
                initialEditValue: geniusToken,
                hint: 'Leave empty for zero-key public search',
                onSave: (val) {
                  ref.read(geniusApiTokenProvider.notifier).state = val;
                  PlaybackSettingsStore.instance.save(geniusApiToken: val);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toggleRow({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.noctraTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: t.primaryText)),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, color: t.tertiaryText)),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _editableRow({
    required BuildContext context,
    required String title,
    required String value,
    String? initialEditValue,
    required String hint,
    required ValueChanged<String> onSave,
  }) {
    final t = context.noctraTokens;
    return InkWell(
      onTap: () async {
        final ctrl = TextEditingController(text: initialEditValue ?? value);
        final saved = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: ctrl,
              decoration: InputDecoration(hintText: hint),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                  child: const Text('Save')),
            ],
          ),
        );
        if (saved != null) onSave(saved);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(fontSize: 13, color: t.primaryText)),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: t.secondaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
