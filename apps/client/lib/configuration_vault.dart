import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config_bundle.dart';
import 'credential_box.dart';
import 'node_access.dart';

abstract interface class SecureStringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Uses the platform's protected app storage. Access by a future VPN process
/// or Apple Packet Tunnel extension needs explicit native configuration.
class PlatformSecureStringStore implements SecureStringStore {
  PlatformSecureStringStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Stores one device's verified update. Writing the version floor first means
/// an interrupted update fails closed: the older bundle cannot be reloaded.
class ConfigurationVault {
  ConfigurationVault(this._store, this._verifier);

  static const _bundleKey = 'nona.active_bundle.v1';
  static const _versionKey = 'nona.minimum_bundle_version.v1';
  static const _identityKey = 'nona.bundle_identity.v1';

  final SecureStringStore _store;
  final BundleVerifier _verifier;

  String _identity(String accountId, String deviceId) =>
      jsonEncode([accountId, deviceId]);

  Future<int> _minimumVersion() async {
    final text = await _store.read(_versionKey);
    if (text == null) return 0;
    final value = int.tryParse(text);
    if (value == null || value < 0) {
      throw const BundleException('Invalid saved version floor');
    }
    return value;
  }

  Future<VerifiedBundle> accept(
    String envelopeJson, {
    required String accountId,
    required String deviceId,
    required DateTime now,
  }) async {
    final identity = _identity(accountId, deviceId);
    if (await _store.read(_identityKey) != identity) {
      // A previous account's version floor and bundle must never affect this
      // account. This also drops unbound data from older client builds.
      await clear();
    }
    final floor = await _minimumVersion();
    final verified = await _verifier.verify(
      envelopeJson,
      accountId: accountId,
      deviceId: deviceId,
      minimumVersion: floor,
      now: now,
    );
    await _store.write(_identityKey, identity);
    if (verified.version > floor) {
      await _store.write(_versionKey, verified.version.toString());
    }
    await _store.write(_bundleKey, envelopeJson);
    return verified;
  }

  Future<VerifiedBundle?> load({
    required String accountId,
    required String deviceId,
    required DateTime now,
  }) async {
    if (await _store.read(_identityKey) != _identity(accountId, deviceId)) {
      return null;
    }
    final floor = await _minimumVersion();
    final envelopeJson = await _store.read(_bundleKey);
    if (envelopeJson == null) return null;
    return _verifier.verify(
      envelopeJson,
      accountId: accountId,
      deviceId: deviceId,
      minimumVersion: floor,
      now: now,
    );
  }

  /// Revalidates the saved signature and validity period before opening one
  /// node's credentials for this registered device. Nothing is persisted in
  /// decrypted form.
  Future<List<int>> openNodeCredentials({
    required String accountId,
    required String deviceId,
    required String nodeId,
    required List<int> deviceSeed,
    required DateTime now,
  }) async {
    final bundle = await load(
      accountId: accountId,
      deviceId: deviceId,
      now: now,
    );
    if (bundle == null) {
      throw const BundleException('No saved configuration');
    }
    final node = _findNode(bundle, nodeId);
    return _openNode(bundle, node, accountId, deviceId, nodeId, deviceSeed);
  }

  Future<NodeAccess> openNodeAccess({
    required String accountId,
    required String deviceId,
    required String nodeId,
    required List<int> deviceSeed,
    required DateTime now,
  }) async {
    final bundle = await load(
      accountId: accountId,
      deviceId: deviceId,
      now: now,
    );
    if (bundle == null) {
      throw const BundleException('No saved configuration');
    }
    final node = _findNode(bundle, nodeId);
    final plaintext = await _openNode(
      bundle,
      node,
      accountId,
      deviceId,
      nodeId,
      deviceSeed,
    );
    try {
      return NodeAccess.parse(
        plaintext,
        endpoint: node['endpoint'] as String,
        transports: (node['transports'] as List).cast<String>(),
      );
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Map<String, dynamic> _findNode(VerifiedBundle bundle, String nodeId) {
    for (final item in bundle.payload['nodes'] as List) {
      final node = item as Map<String, dynamic>;
      if (node['id'] == nodeId) return node;
    }
    throw const BundleException('Node is not in the saved configuration');
  }

  Future<List<int>> _openNode(
    VerifiedBundle bundle,
    Map<String, dynamic> node,
    String accountId,
    String deviceId,
    String nodeId,
    List<int> deviceSeed,
  ) => const CredentialBox().open(
    encoded: node['encrypted_credentials'] as String,
    deviceSeed: deviceSeed,
    context: CredentialContext(
      accountId: accountId,
      deviceId: deviceId,
      nodeId: nodeId,
      version: bundle.version,
    ),
  );

  Future<void> clear() async {
    await _store.delete(_bundleKey);
    await _store.delete(_versionKey);
    await _store.delete(_identityKey);
  }
}
