import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/config_bundle.dart';
import 'package:nona_client/configuration_vault.dart';

class MemoryStore implements SecureStringStore {
  final values = <String, String>{};
  bool failOnBundleWrite = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failOnBundleWrite && key == 'nona.active_bundle.v1') {
      throw StateError('interrupted write');
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  final fixture = jsonDecode(
    File('../../test-vectors/config-bundle.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final publicKey = base64Url.decode(
    base64Url.normalize(fixture['public_key_b64'] as String),
  );
  final envelope = jsonEncode(fixture['envelope']);
  final now = DateTime.utc(2026, 11, 9, 12);
  final verifier = BundleVerifier({'test-key-1': publicKey});

  test('stores and reloads only a verified update', () async {
    final store = MemoryStore();
    final vault = ConfigurationVault(store, verifier);
    await vault.accept(
      envelope,
      accountId: 'account-a',
      deviceId: 'device-a',
      now: now,
    );
    final loaded = await vault.load(
      accountId: 'account-a',
      deviceId: 'device-a',
      now: now,
    );
    expect(loaded?.version, 2);
    await vault.clear();
    expect(
      await vault.load(accountId: 'account-a', deviceId: 'device-a', now: now),
      isNull,
    );
  });

  test('an interrupted replacement fails closed', () async {
    final store = MemoryStore()..failOnBundleWrite = true;
    final vault = ConfigurationVault(store, verifier);
    await expectLater(
      vault.accept(
        envelope,
        accountId: 'account-a',
        deviceId: 'device-a',
        now: now,
      ),
      throwsStateError,
    );
    expect(store.values['nona.minimum_bundle_version.v1'], '2');
    expect(
      await vault.load(accountId: 'account-a', deviceId: 'device-a', now: now),
      isNull,
    );
  });

  test('refuses a corrupted version floor', () async {
    final store = MemoryStore();
    store.values['nona.minimum_bundle_version.v1'] = 'bad';
    final vault = ConfigurationVault(store, verifier);
    await expectLater(
      vault.accept(
        envelope,
        accountId: 'account-a',
        deviceId: 'device-a',
        now: now,
      ),
      throwsA(isA<BundleException>()),
    );
  });

  test('opens only credentials from a verified saved node', () async {
    final credentialVector = jsonDecode(
      File('../../test-vectors/credential-box.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final payload = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(
            (fixture['envelope'] as Map<String, dynamic>)['payload_b64']
                as String,
          ),
        ),
      ),
    ) as Map<String, dynamic>;
    (payload['nodes'] as List).single['encrypted_credentials'] =
        credentialVector['sealed'];
    final keyPair = await Ed25519().newKeyPair();
    final bytes = utf8.encode(jsonEncode(payload));
    final signature = await Ed25519().sign([
      ...utf8.encode('NONA-CONFIG-BUNDLE-v1\u0000'),
      ...bytes,
    ], keyPair: keyPair);
    final signed = jsonEncode({
      'key_id': 'test-key-2',
      'payload_b64': base64UrlEncode(bytes).replaceAll('=', ''),
      'signature': base64UrlEncode(signature.bytes).replaceAll('=', ''),
    });
    final vault = ConfigurationVault(
      MemoryStore(),
      BundleVerifier({'test-key-2': (await keyPair.extractPublicKey()).bytes}),
    );
    await vault.accept(
      signed,
      accountId: 'account-a',
      deviceId: 'device-a',
      now: now,
    );
    final seed = base64Url.decode(
      base64Url.normalize(credentialVector['device_seed_b64'] as String),
    );
    final opened = await vault.openNodeCredentials(
      accountId: 'account-a',
      deviceId: 'device-a',
      nodeId: 'node-a',
      deviceSeed: seed,
      now: now,
    );
    expect(utf8.decode(opened), credentialVector['plaintext']);
    await expectLater(
      vault.openNodeCredentials(
        accountId: 'account-a',
        deviceId: 'device-a',
        nodeId: 'unknown',
        deviceSeed: seed,
        now: now,
      ),
      throwsA(isA<BundleException>()),
    );
  });
}
