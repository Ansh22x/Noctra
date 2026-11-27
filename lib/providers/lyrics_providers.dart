import 'package:flutter_riverpod/legacy.dart';
import '../core/utils/playback_settings_store.dart';

final whisperxEnabledProvider = StateProvider<bool>(
  (ref) => PlaybackSettingsStore.instance.whisperxEnabled,
);

final whisperxEndpointProvider = StateProvider<String>(
  (ref) => PlaybackSettingsStore.instance.whisperxEndpoint,
);

final geniusApiTokenProvider = StateProvider<String>(
  (ref) => PlaybackSettingsStore.instance.geniusApiToken,
);

final autoTranslateLyricsProvider = StateProvider<bool>(
  (ref) => PlaybackSettingsStore.instance.autoTranslateNonEnglish,
);
