import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../data/models/song_model.dart';
import '../lyrics_matcher.dart';
import '../lyrics_service.dart';

class WhisperXSegment {
  final Duration start;
  final Duration end;
  final String text;
  const WhisperXSegment({required this.start, required this.end, required this.text});
}

/// Synchronizes Genius (or plain-text) lyrics against audio using WhisperX,
/// or transcribes+aligns audio directly via HTTP sidecar or desktop CLI.
class WhisperXSyncService {
  static const String defaultEndpoint = 'http://127.0.0.1:8765';

  static Future<LyricsData?> syncWithWhisperX({
    required Song song,
    String? referenceLyrics,
    String endpointUrl = defaultEndpoint,
    String sourceLabel = 'whisperx+genius',
    http.Client? client,
  }) async {
    final cleanEndpoint = endpointUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleanEndpoint.isNotEmpty) {
      final httpResult = await _alignViaHttp(
        song: song,
        referenceLyrics: referenceLyrics,
        endpointUrl: cleanEndpoint,
        sourceLabel: sourceLabel,
        client: client,
      );
      if (httpResult != null) return httpResult;
    }
    if ((Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        song.localFilePath != null &&
        song.localFilePath!.isNotEmpty &&
        File(song.localFilePath!).existsSync()) {
      return _alignViaLocalCli(
        audioPath: song.localFilePath!,
        referenceLyrics: referenceLyrics,
        sourceLabel: sourceLabel,
      );
    }
    return null;
  }

  static Future<LyricsData?> _alignViaHttp({
    required Song song,
    String? referenceLyrics,
    required String endpointUrl,
    required String sourceLabel,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      final res = await httpClient
          .post(
            Uri.parse('$endpointUrl/align'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': song.title,
              'artist': song.artist,
              'duration_sec': song.duration.inSeconds,
              if (song.localFilePath != null && song.localFilePath!.isNotEmpty)
                'audio_path': song.localFilePath,
              if (song.streamUrl != null && song.streamUrl!.isNotEmpty)
                'audio_url': song.streamUrl,
              if (referenceLyrics != null && referenceLyrics.trim().isNotEmpty)
                'lyrics': referenceLyrics,
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      return parseWhisperXResponse(decoded,
          referenceLyrics: referenceLyrics, sourceLabel: sourceLabel);
    } catch (_) {
      return null;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static LyricsData? parseWhisperXResponse(
    Map<String, dynamic> json, {
    String? referenceLyrics,
    String sourceLabel = 'whisperx+genius',
  }) {
    final syncedLrc = json['synced_lrc'] as String?;
    if (syncedLrc != null && syncedLrc.trim().isNotEmpty) {
      final parsed = LyricsMatcher.parseLrc(syncedLrc);
      if (parsed.isNotEmpty) {
        return LyricsData(
          isSynced: true,
          lines: parsed,
          plainText: parsed.map((l) => l.text).join('\n'),
          source: sourceLabel,
        );
      }
    }
    final rawList = (json['lines'] ?? json['segments']) as List?;
    if (rawList == null || rawList.isEmpty) return null;

    final segments = <WhisperXSegment>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final text = (item['text'] as String?)?.trim() ?? '';
      final startSec = (item['start'] as num?)?.toDouble();
      final endSec = (item['end'] as num?)?.toDouble();
      if (text.isEmpty || startSec == null) continue;
      segments.add(WhisperXSegment(
        start: Duration(milliseconds: (startSec * 1000).round()),
        end: Duration(milliseconds: ((endSec ?? (startSec + 2.5)) * 1000).round()),
        text: text,
      ));
    }
    if (segments.isEmpty) return null;

    final bool alreadyAligned = json['forced_aligned'] == true;
    List<LyricLine> finalLines;
    if (!alreadyAligned &&
        referenceLyrics != null &&
        referenceLyrics.trim().isNotEmpty) {
      final refLines = prepareReferenceLines(referenceLyrics);
      finalLines = refLines.isNotEmpty
          ? alignReferenceLinesToSegments(refLines, segments)
          : segments.map((s) => LyricLine(timestamp: s.start, text: s.text)).toList();
    } else {
      finalLines =
          segments.map((s) => LyricLine(timestamp: s.start, text: s.text)).toList();
    }
    if (finalLines.isEmpty) return null;
    return LyricsData(
      isSynced: true,
      lines: finalLines,
      plainText: finalLines.map((l) => l.text).join('\n'),
      source: sourceLabel,
    );
  }

  static List<String> prepareReferenceLines(String plainLyrics) {
    final headerRe = RegExp(r'^\[.*\]$');
    return plainLyrics
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !headerRe.hasMatch(l))
        .toList();
  }

  static List<LyricLine> alignReferenceLinesToSegments(
    List<String> refLines,
    List<WhisperXSegment> segments,
  ) {
    if (refLines.isEmpty || segments.isEmpty) return const [];
    final totalStartMs = segments.first.start.inMilliseconds;
    final totalEndMs = segments.last.end.inMilliseconds;
    final matchedMs = List<int?>.filled(refLines.length, null);

    int segCursor = 0;
    for (int i = 0; i < refLines.length; i++) {
      final refTokens = _tokens(refLines[i]);
      if (refTokens.isEmpty) continue;
      double bestScore = 0.0;
      int bestSegIdx = -1;
      final searchEnd = (segCursor + 8).clamp(0, segments.length);
      for (int j = segCursor; j < searchEnd; j++) {
        final segTokens = _tokens(segments[j].text);
        if (segTokens.isEmpty) continue;
        final score = refTokens.intersection(segTokens).length / refTokens.length;
        if (score > bestScore) {
          bestScore = score;
          bestSegIdx = j;
        }
      }
      if (bestSegIdx >= 0 && bestScore >= 0.34) {
        matchedMs[i] = segments[bestSegIdx].start.inMilliseconds;
        segCursor = bestSegIdx + 1;
      }
    }

    for (int i = 0; i < refLines.length; i++) {
      if (matchedMs[i] != null) continue;
      int prevIdx = i - 1;
      while (prevIdx >= 0 && matchedMs[prevIdx] == null) {
        prevIdx--;
      }
      int nextIdx = i + 1;
      while (nextIdx < refLines.length && matchedMs[nextIdx] == null) {
        nextIdx++;
      }
      final prevMs = prevIdx >= 0 ? matchedMs[prevIdx]! : totalStartMs;
      final nextMs = nextIdx < refLines.length ? matchedMs[nextIdx]! : totalEndMs;
      final span = (nextIdx - prevIdx).clamp(1, refLines.length + 1);
      matchedMs[i] = (prevMs + ((nextMs - prevMs) / span) * (i - prevIdx)).round();
    }

    return List<LyricLine>.generate(
      refLines.length,
      (i) => LyricLine(
        timestamp: Duration(milliseconds: matchedMs[i]!.clamp(0, 36000000)),
        text: refLines[i],
      ),
    );
  }

  static Set<String> _tokens(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toSet();

  static Future<LyricsData?> _alignViaLocalCli({
    required String audioPath,
    String? referenceLyrics,
    required String sourceLabel,
  }) async {
    Directory? tmpDir;
    try {
      tmpDir = await Directory.systemTemp.createTemp('noctra_wx_');
      final result = await Process.run('whisperx', [
        audioPath,
        '--output_format',
        'json',
        '--output_dir',
        tmpDir.path,
        '--compute_type',
        'int8',
      ]).timeout(const Duration(seconds: 90));
      if (result.exitCode != 0) return null;
      final jsonFiles = tmpDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      if (jsonFiles.isEmpty) return null;
      final decoded = jsonDecode(await jsonFiles.first.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return parseWhisperXResponse(decoded,
          referenceLyrics: referenceLyrics, sourceLabel: sourceLabel);
    } catch (_) {
      return null;
    } finally {
      try {
        tmpDir?.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}
