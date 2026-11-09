import 'dart:convert';
import 'dart:io';

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
}
