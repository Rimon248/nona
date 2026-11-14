import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nona_client/app_update.dart';

void main() {
  test('release versions are compared numerically', () {
    expect(isNewerVersion('0.1.10', '0.1.9'), isTrue);
    expect(isNewerVersion('0.2.0', '0.10.0'), isFalse);
    expect(isNewerVersion('0.1.1', '0.1.1'), isFalse);
    expect(isNewerVersion('0.1.2-beta', '0.1.1'), isFalse);
  });

  test('Android accepts only the matching GitHub APK and SHA-256', () async {
    final client = MockClient((request) async {
      expect(request.url, GitHubUpdateChecker.releaseApi);
      return http.Response(
        jsonEncode({
          'tag_name': 'v0.1.2',
          'assets': [
            {
              'name': 'nona-v0.1.2-android.apk',
              'browser_download_url': 'https://github.com/Rimon248/nona/releases/download/v0.1.2/nona-v0.1.2-android.apk',
              'digest': 'sha256:${'a' * 64}',
            },
          ],
        }),
        200,
      );
    });
    final update = await GitHubUpdateChecker(client)
        .check(installedVersion: '0.1.1', platform: TargetPlatform.android);
    expect(update?.version, '0.1.2');
    expect(update?.sha256, 'a' * 64);
    client.close();
  });

  test('untrusted release download addresses are ignored', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'tag_name': 'v0.1.2',
          'assets': [
            {
              'name': 'nona-v0.1.2-android.apk',
              'browser_download_url': 'https://example.com/Rimon248/nona/releases/download/v0.1.2/nona-v0.1.2-android.apk',
              'digest': 'sha256:${'a' * 64}',
            },
          ],
        }),
        200,
      ),
    );
    expect(
      await GitHubUpdateChecker(client)
          .check(installedVersion: '0.1.1', platform: TargetPlatform.android),
      isNull,
    );
    client.close();
  });
}
