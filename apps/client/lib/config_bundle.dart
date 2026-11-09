import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'credential_box.dart';

const _domainPrefix = 'NONA-CONFIG-BUNDLE-v1\u0000';
const _maxPayloadSize = 1 << 20;

class BundleException implements Exception {
  const BundleException(this.message);
  final String message;

  @override
  String toString() => 'BundleException: $message';
}

class VerifiedBundle {
  const VerifiedBundle({required this.version, required this.payload});
  final int version;
  final Map<String, dynamic> payload;
}

/// Verifies a server update before it can replace local configuration.
/// Trusted public keys and the minimum accepted version must come from the
/// app's trusted state, never from the same server response being verified.
class BundleVerifier {
  BundleVerifier(this.trustedKeys);

  final Map<String, List<int>> trustedKeys;

  Future<VerifiedBundle> verify(
    String envelopeJson, {
    required String accountId,
    required String deviceId,
    required int minimumVersion,
    required DateTime now,
  }) async {
    final dynamic decodedEnvelope;
    try {
      decodedEnvelope = jsonDecode(envelopeJson);
    } catch (_) {
      throw const BundleException('Invalid envelope JSON');
    }
    if (decodedEnvelope is! Map<String, dynamic> ||
        !_hasExactly(decodedEnvelope, {'key_id', 'payload_b64', 'signature'})) {
      throw const BundleException('Invalid envelope fields');
    }
    final keyId = decodedEnvelope['key_id'];
    final payloadB64 = decodedEnvelope['payload_b64'];
    final signatureB64 = decodedEnvelope['signature'];
    if (keyId is! String || payloadB64 is! String || signatureB64 is! String) {
      throw const BundleException('Invalid envelope field types');
    }
    final publicKeyBytes = trustedKeys[keyId];
    if (publicKeyBytes == null || publicKeyBytes.length != 32) {
      throw const BundleException('Unknown signing key');
    }
    final List<int> payloadBytes;
    final List<int> signatureBytes;
    try {
      payloadBytes = base64Url.decode(base64Url.normalize(payloadB64));
      signatureBytes = base64Url.decode(base64Url.normalize(signatureB64));
    } catch (_) {
      throw const BundleException('Invalid base64 encoding');
    }
    if (payloadBytes.isEmpty ||
        payloadBytes.length > _maxPayloadSize ||
        signatureBytes.length != 64) {
      throw const BundleException('Invalid payload or signature size');
    }
    final message = [...utf8.encode(_domainPrefix), ...payloadBytes];
    final signature = Signature(
      signatureBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    );
    if (!await Ed25519().verify(message, signature: signature)) {
      throw const BundleException('Invalid signature');
    }

    final String payloadText;
    final dynamic payload;
    try {
      payloadText = utf8.decode(payloadBytes);
      payload = jsonDecode(payloadText);
    } catch (_) {
      throw const BundleException('Invalid payload JSON');
    }
    if (payload is! Map<String, dynamic> ||
        !_hasExactly(payload, {
          'schema_version',
          'account_id',
          'device_id',
          'version',
          'issued_at',
          'expires_at',
          'rules_version',
          'nodes',
        }) ||
        jsonEncode(payload) != payloadText) {
      throw const BundleException('Noncanonical payload');
    }
    final version = payload['version'];
    final rulesVersion = payload['rules_version'];
    final issuedAtText = payload['issued_at'];
    final expiresAtText = payload['expires_at'];
    final nodes = payload['nodes'];
    if (payload['schema_version'] != 1 ||
        payload['account_id'] != accountId ||
        payload['device_id'] != deviceId ||
        version is! int ||
        version < 1 ||
        version < minimumVersion ||
        rulesVersion is! int ||
        rulesVersion < 1 ||
        issuedAtText is! String ||
        expiresAtText is! String ||
        nodes is! List ||
        nodes.isEmpty) {
      throw const BundleException('Invalid bundle identity or version');
    }
    final issuedAt = DateTime.tryParse(issuedAtText)?.toUtc();
    final expiresAt = DateTime.tryParse(expiresAtText)?.toUtc();
    final instant = now.toUtc();
    if (issuedAt == null ||
        expiresAt == null ||
        !expiresAt.isAfter(issuedAt) ||
        instant.isBefore(issuedAt.subtract(const Duration(minutes: 5))) ||
        !instant.isBefore(expiresAt)) {
      throw const BundleException('Bundle is not currently valid');
    }
    final nodeIds = <String>{};
    for (final node in nodes) {
      if (node is! Map<String, dynamic> ||
          !_hasExactly(node, {
            'id',
            'provider',
            'endpoint',
            'transports',
            'encrypted_credentials',
          }) ||
          node['id'] is! String ||
          (node['id'] as String).isEmpty ||
          node['provider'] is! String ||
          (node['provider'] as String).isEmpty ||
          node['endpoint'] is! String ||
          (node['endpoint'] as String).isEmpty ||
          node['encrypted_credentials'] is! String ||
          (node['encrypted_credentials'] as String).isEmpty ||
          node['transports'] is! List ||
          (node['transports'] as List).isEmpty ||
          !(node['transports'] as List).every(
            (value) => value is String && value.isNotEmpty,
          ) ||
          !nodeIds.add(node['id'] as String)) {
        throw const BundleException('Invalid or duplicate node');
      }
      try {
        CredentialBox.validateEnvelope(node['encrypted_credentials'] as String);
      } on CredentialException {
        throw const BundleException('Invalid encrypted credentials');
      }
    }
    return VerifiedBundle(version: version, payload: payload);
  }
}

bool _hasExactly(Map<String, dynamic> map, Set<String> keys) =>
    map.length == keys.length && map.keys.toSet().containsAll(keys);
