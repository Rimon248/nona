import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nona_client/auth_client.dart';
import 'package:nona_client/config_bundle.dart';
import 'package:nona_client/configuration_sync.dart';
import 'package:nona_client/configuration_vault.dart';

class _Store implements SecureStringStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  const deviceId = '0123456789abcdef0123456789abcdef';
  final now = DateTime.utc(2026, 11, 9, 12);

  test(
    'syncs a signed update and removes it after server withdrawal',
    () async {
      final vector = jsonDecode(
        File('../../test-vectors/credential-box.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final payload = {
        'schema_version': 1,
        'account_id': 'account-a',
        'device_id': deviceId,
        'version': 2,
        'issued_at': '2026-11-09T11:59:00Z',
        'expires_at': '2026-11-09T13:00:00Z',
        'rules_version': 1,
        'nodes': [
          {
            'id': 'node-a',
            'provider': 'vdsina',
            'endpoint': 'example.invalid',
            'transports': ['vless-reality'],
            'encrypted_credentials': vector['sealed'],
          },
        ],
      };
      final keyPair = await Ed25519().newKeyPair();
      final bytes = utf8.encode(jsonEncode(payload));
      final signature = await Ed25519().sign([
        ...utf8.encode('NONA-CONFIG-BUNDLE-v1\u0000'),
        ...bytes,
      ], keyPair: keyPair);
      final envelope = jsonEncode({
        'key_id': 'test',
        'payload_b64': base64UrlEncode(bytes).replaceAll('=', ''),
        'signature': base64UrlEncode(signature.bytes).replaceAll('=', ''),
      });
      var responseCode = 200;
      var responseBody = envelope;
      final auth = AuthClient(
        baseUri: Uri.parse('https://accounts.example.invalid'),
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/sessions') {
            return http.Response(
              jsonEncode({
                'account_id': 'account-a',
                'access_token': 'access',
                'access_expires_at': '2026-11-09T12:15:00Z',
                'refresh_token': 'refresh',
                'refresh_expires_at': '2026-12-09T12:00:00Z',
              }),
              200,
            );
          }
          expect(request.headers['authorization'], 'Bearer access');
          expect(request.url.path, '/v1/devices/$deviceId/configuration');
          return http.Response(responseBody, responseCode);
        }),
        secureStore: _Store(),
      );
      await auth.login('alice', 'test password');
      final vault = ConfigurationVault(
        _Store(),
        BundleVerifier({'test': (await keyPair.extractPublicKey()).bytes}),
      );
      final sync = ConfigurationSync(auth, vault);
      expect((await sync.refresh(deviceId: deviceId, now: now))?.version, 2);
      responseBody = envelope.replaceFirst('test', 'bad!');
      await expectLater(
        sync.refresh(deviceId: deviceId, now: now),
        throwsA(isA<BundleException>()),
      );
      expect(
        (await vault.load(
          accountId: 'account-a',
          deviceId: deviceId,
          now: now,
        ))?.version,
        2,
      );
      responseCode = 404;
      responseBody = '';
      expect(await sync.refresh(deviceId: deviceId, now: now), isNull);
      expect(
        await vault.load(accountId: 'account-a', deviceId: deviceId, now: now),
        isNull,
      );
    },
  );
}
