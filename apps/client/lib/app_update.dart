import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class AppUpdate {
  const AppUpdate({
    required this.tag,
    required this.version,
    required this.downloadUrl,
    required this.sha256,
  });

  final String tag;
  final String version;
  final Uri downloadUrl;
  final String sha256;
}

/// Checks published GitHub releases. Preview workflow artifacts are not updates.
class GitHubUpdateChecker {
  const GitHubUpdateChecker(this.client);

  static final Uri releaseApi = Uri.https(
    'api.github.com',
    '/repos/Rimon248/nona/releases/latest',
  );
  final http.Client client;

  Future<AppUpdate?> check({
    required String installedVersion,
    required TargetPlatform platform,
  }) async {
    final response = await client
        .get(
          releaseApi,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'Nona-App-Update-Check',
          },
        )
        .timeout(const Duration(seconds: 7));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) return null;
    final tag = data['tag_name'];
    if (tag is! String) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (!isNewerVersion(version, installedVersion)) return null;

    final suffix = switch (platform) {
      TargetPlatform.android => '-android.apk',
      TargetPlatform.macOS => '-macos.zip',
      TargetPlatform.windows => '-windows.zip',
      _ => null,
    };
    if (suffix == null) return null;
    final assets = data['assets'];
    if (assets is! List) return null;
    for (final raw in assets) {
      if (raw is! Map<String, dynamic>) continue;
      final name = raw['name'];
      final address = raw['browser_download_url'];
      final digest = raw['digest'];
      if (name is! String ||
          name != 'nona-$tag$suffix' ||
          address is! String ||
          digest is! String ||
          !digest.startsWith('sha256:')) {
        continue;
      }
      final uri = Uri.tryParse(address);
      final sha256 = digest.substring('sha256:'.length).toLowerCase();
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          !uri.path.startsWith('/Rimon248/nona/releases/download/') ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
        continue;
      }
      return AppUpdate(
        tag: tag,
        version: version,
        downloadUrl: uri,
        sha256: sha256,
      );
    }
    return null;
  }
}

bool isNewerVersion(String candidate, String installed) {
  List<int>? parse(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$')
        .firstMatch(value);
    if (match == null) return null;
    return [for (var part = 1; part <= 3; part++) int.parse(match[part]!)];
  }

  final newer = parse(candidate);
  final current = parse(installed);
  if (newer == null || current == null) return false;
  for (var index = 0; index < 3; index++) {
    if (newer[index] > current[index]) return true;
    if (newer[index] < current[index]) return false;
  }
  return false;
}

class AndroidAppInstaller {
  static const _channel = MethodChannel('nona.app_update');

  Future<void> install(AppUpdate update) async {
    await _channel.invokeMethod<void>('install', {
      'url': update.downloadUrl.toString(),
      'sha256': update.sha256,
      'tag': update.tag,
    });
  }
}
