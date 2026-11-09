import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/config_bundle.dart';

Future<(String, List<int>)> signedFixture({
  String? encryptedCredentials,
}) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final credentialVector = jsonDecode(
    File('../../test-vectors/credential-box.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final payload = {
    'schema_version': 1,
    'account_id': 'account-a',
    'device_id': 'device-a',
    'version': 2,
    'issued_at': '2026-11-09T11:59:00Z',
    'expires_at': '2026-11-09T13:00:00Z',
    'rules_version': 1,
    'nodes': [
      {
        'id': 'node-a',
        'provider': 'vdsina',
        'endpoint': 'example.invalid',
        'transports': ['vless-reality', 'hysteria2'],
        'encrypted_credentials':
            encryptedCredentials ?? credentialVector['sealed'],
      },
    ],
  };
  final bytes = utf8.encode(jsonEncode(payload));
  final message = [...utf8.encode('NONA-CONFIG-BUNDLE-v1\u0000'), ...bytes];
  final signature = await algorithm.sign(message, keyPair: keyPair);
  String rawUrl(List<int> input) => base64Url.encode(input).replaceAll('=', '');
  final envelope = jsonEncode({
    'key_id': 'key-1',
    'payload_b64': rawUrl(bytes),
    'signature': rawUrl(signature.bytes),
  });
  return (envelope, publicKey.bytes);
}

void main() {
  final now = DateTime.utc(2026, 11, 9, 12);

  test('verifies the Go-generated bundle vector', () async {
    final fixture = jsonDecode(
      File('../../test-vectors/config-bundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final key = base64Url.decode(
      base64Url.normalize(fixture['public_key_b64'] as String),
    );
    final bundle = await BundleVerifier({'test-key-1': key}).verify(
      jsonEncode(fixture['envelope']),
      accountId: 'account-a',
      deviceId: 'device-a',
      minimumVersion: 2,
      now: now,
    );
    expect(bundle.version, 2);
  });

  test('accepts a signed bundle for the expected device', () async {
    final (envelope, key) = await signedFixture();
    final verified = await BundleVerifier({'key-1': key}).verify(
      envelope,
      accountId: 'account-a',
      deviceId: 'device-a',
      minimumVersion: 2,
      now: now,
    );
    expect(verified.version, 2);
  });

  test('rejects signed plaintext in the credentials field', () async {
    final (envelope, key) = await signedFixture(
      encryptedCredentials: 'plaintext-password',
    );
    await expectLater(
      BundleVerifier({'key-1': key}).verify(
        envelope,
        accountId: 'account-a',
        deviceId: 'device-a',
        minimumVersion: 2,
        now: now,
      ),
      throwsA(isA<BundleException>()),
    );
  });

  test('rejects tampering, wrong device, rollback and expiry', () async {
    final (envelope, key) = await signedFixture();
    final verifier = BundleVerifier({'key-1': key});
    final decoded = jsonDecode(envelope) as Map<String, dynamic>;
    final payload = base64Url.decode(
      base64Url.normalize(decoded['payload_b64'] as String),
    );
    payload[10] ^= 1;
    decoded['payload_b64'] = base64Url.encode(payload).replaceAll('=', '');
    await expectLater(
      verifier.verify(
        jsonEncode(decoded),
        accountId: 'account-a',
        deviceId: 'device-a',
        minimumVersion: 2,
        now: now,
      ),
      throwsA(isA<BundleException>()),
    );
    for (final (deviceId, minimumVersion, instant) in [
      ('device-b', 2, now),
      ('device-a', 3, now),
      ('device-a', 2, now.add(const Duration(hours: 2))),
    ]) {
      await expectLater(
        verifier.verify(
          envelope,
          accountId: 'account-a',
          deviceId: deviceId,
          minimumVersion: minimumVersion,
          now: instant,
        ),
        throwsA(isA<BundleException>()),
      );
    }
  });
}
