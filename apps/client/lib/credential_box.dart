import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Decrypts the access data inside a verified configuration bundle.
/// Call only after BundleVerifier has checked the signed account, device,
/// node and version. The device seed comes from protected app storage.
class CredentialException implements Exception {
  const CredentialException(this.message);
  final String message;
}

class CredentialContext {
  const CredentialContext({
    required this.accountId,
    required this.deviceId,
    required this.nodeId,
    required this.version,
  });

  final String accountId;
  final String deviceId;
  final String nodeId;
  final int version;

  List<int> associatedData() {
    for (final value in [accountId, deviceId, nodeId]) {
      if (value.isEmpty ||
          utf8.encode(value).length > 256 ||
          value.contains('\u0000')) {
        throw const CredentialException('Invalid credential context');
      }
    }
    if (version < 1) {
      throw const CredentialException('Invalid credential version');
    }
    return utf8.encode(
      'NONA-CREDENTIALS-v1\u0000$accountId\u0000$deviceId\u0000$nodeId\u0000$version',
    );
  }
}

class CredentialBox {
  const CredentialBox();

  static final _encoding = RegExp(r'^[A-Za-z0-9_-]+$');

  static List<int> _decode(String value) {
    if (value.isEmpty || !_encoding.hasMatch(value)) {
      throw const CredentialException('Invalid credential envelope');
    }
    try {
      final result = base64Url.decode(base64Url.normalize(value));
      if (base64UrlEncode(result).replaceAll('=', '') != value) {
        throw const CredentialException('Invalid credential envelope');
      }
      return result;
    } on FormatException {
      throw const CredentialException('Invalid credential envelope');
    }
  }

  static (List<int>, List<int>, List<int>) _parse(String encoded) {
    if (encoded.length > 8192) {
      throw const CredentialException('Invalid credential envelope');
    }
    final parts = encoded.split('.');
    if (parts.length != 4 || parts.first != 'v1') {
      throw const CredentialException('Invalid credential envelope');
    }
    final ephemeral = _decode(parts[1]);
    final nonce = _decode(parts[2]);
    final sealed = _decode(parts[3]);
    if (ephemeral.length != 32 ||
        nonce.length != 12 ||
        sealed.length < 17 ||
        sealed.length > 4112) {
      throw const CredentialException('Invalid credential envelope');
    }
    return (ephemeral, nonce, sealed);
  }

  /// Checks that a signed bundle contains an encrypted field, not plaintext.
  static void validateEnvelope(String encoded) {
    _parse(encoded);
  }

  Future<List<int>> open({
    required String encoded,
    required List<int> deviceSeed,
    required CredentialContext context,
  }) async {
    final aad = context.associatedData();
    if (deviceSeed.length != 32) {
      throw const CredentialException('Invalid credential input');
    }
    final (ephemeral, nonce, sealed) = _parse(encoded);
    try {
      final algorithm = X25519();
      final keyPair = await algorithm.newKeyPairFromSeed(deviceSeed);
      final shared = await algorithm.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: SimplePublicKey(ephemeral, type: KeyPairType.x25519),
      );
      final sharedBytes = await shared.extractBytes();
      if (sharedBytes.every((value) => value == 0)) {
        throw const CredentialException('Invalid ephemeral key');
      }
      final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(sharedBytes),
        nonce: utf8.encode('NONA-CREDENTIALS-v1'),
        info: aad,
      );
      final box = SecretBox(
        sealed.sublist(0, sealed.length - 16),
        nonce: nonce,
        mac: Mac(sealed.sublist(sealed.length - 16)),
      );
      return await AesGcm.with256bits().decrypt(box, secretKey: key, aad: aad);
    } on CredentialException {
      rethrow;
    } catch (_) {
      throw const CredentialException('Credential authentication failed');
    }
  }
}
