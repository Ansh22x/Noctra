import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctra/services/updater/app_update_manifest.dart';

/// Verifies the artifacts staged by `tool/build_release.sh`, which writes to
/// `build/release/`. Those APKs are build outputs and never committed, so this
/// file is tagged `release` and skipped unless a release has been staged.
void main() {
  const releaseDir = 'build/release';

  group('Release Manifest & Artifact Integrity Verification', () {
    test('noctra-update-manifest.json parses strictly and matches staged APKs',
        () {
      final manifestFile = File('$releaseDir/noctra-update-manifest.json');
      expect(manifestFile.existsSync(), isTrue,
          reason: 'Run tool/build_release.sh to stage release artifacts');

      final manifest = ReleaseManifest.parse(manifestFile.readAsStringSync());
      expect(manifest, isNotNull, reason: 'Manifest must pass ReleaseManifest.parse');

      // Version identity comes from pubspec.yaml, the single source of truth.
      final expected = _pubspecVersion();
      expect(manifest!.version, equals(expected.version));
      expect(manifest.versionCode, equals(expected.buildCode));
      expect(manifest.minimumAndroid, equals(_minSdkFromGradle()));

      expect(manifest.packages.keys, containsAll(<String>['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal']));

      for (final entry in manifest.packages.entries) {
        final abi = entry.key;
        final pkg = entry.value;
        final apkFile = File('$releaseDir/${pkg.file}');
        expect(apkFile.existsSync(), isTrue, reason: 'APK ${pkg.file} for $abi must exist');

        final digest = sha256.convert(apkFile.readAsBytesSync()).toString();
        expect(digest, equals(pkg.sha256.toLowerCase()),
            reason: 'SHA-256 in manifest for $abi must match physical file');
      }
    }, tags: 'release');

    test('SHA256SUMS.txt matches staged APKs', () {
      final sumsFile = File('$releaseDir/SHA256SUMS.txt');
      expect(sumsFile.existsSync(), isTrue,
          reason: 'Run tool/build_release.sh to stage release artifacts');

      final lines = sumsFile.readAsLinesSync().where((l) => l.trim().isNotEmpty);
      expect(lines, isNotEmpty);
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        expect(parts.length, equals(2));
        final expectedHash = parts[0].toLowerCase();
        final fileName = parts[1];

        final apkFile = File('$releaseDir/$fileName');
        expect(apkFile.existsSync(), isTrue, reason: '$fileName must exist');

        final digest = sha256.convert(apkFile.readAsBytesSync()).toString();
        expect(digest, equals(expectedHash), reason: '$fileName hash must match SHA256SUMS.txt');
      }
    }, tags: 'release');
  });
}

/// Reads `version: x.y.z+buildCode` from pubspec.yaml.
({String version, int buildCode}) _pubspecVersion() {
  final line = File('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  final value = line.substring('version:'.length).trim();
  final plus = value.indexOf('+');
  if (plus < 0) return (version: value, buildCode: 0);
  return (
    version: value.substring(0, plus),
    buildCode: int.parse(value.substring(plus + 1)),
  );
}

/// Reads `minSdk = NN` from the Android Gradle config, mirroring the release
/// script so the manifest cannot silently drift from what the APKs target.
int _minSdkFromGradle() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final match = RegExp(r'minSdk\s*=\s*(\d+)').firstMatch(gradle);
  expect(match, isNotNull, reason: 'minSdk must be declared in build.gradle.kts');
  return int.parse(match!.group(1)!);
}
