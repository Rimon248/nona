import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/credential_box.dart';

void main() {
  final vector = jsonDecode(
    File('../../test-vectors/credential-box.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final data = vector['context'] as Map<String, dynamic>;
  final context = CredentialContext(
    accountId: data['account_id'] as String,
    deviceId: data['device_id'] as String,
    nodeId: data['node_id'] as String,
    version: data['version'] as int,
  );
  final seed = base64Url.decode(
    base64Url.normalize(vector['device_seed_b64'] as String),
  );

  test('opens Go-sealed credentials for the registered device', () async {
    final plaintext = await const CredentialBox().open(
      encoded: vector['sealed'] as String,
      deviceSeed: seed,
      context: context,
    );
    expect(utf8.decode(plaintext), vector['plaintext']);
  });

  test('rejects another bundle version and changed ciphertext', () async {
    await expectLater(
      const CredentialBox().open(
        encoded: vector['sealed'] as String,
        deviceSeed: seed,
        context: CredentialContext(
          accountId: context.accountId,
          deviceId: context.deviceId,
          nodeId: context.nodeId,
          version: context.version + 1,
        ),
      ),
      throwsA(isA<CredentialException>()),
    );
    final parts = (vector['sealed'] as String).split('.');
    parts[3] =
        '${parts[3].startsWith('A') ? 'B' : 'A'}${parts[3].substring(1)}';
    await expectLater(
      const CredentialBox().open(
        encoded: parts.join('.'),
        deviceSeed: seed,
        context: context,
      ),
      throwsA(isA<CredentialException>()),
    );
  });
}
