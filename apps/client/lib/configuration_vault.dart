import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config_bundle.dart';
import 'credential_box.dart';

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

  final SecureStringStore _store;
  final BundleVerifier _verifier;

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
    final floor = await _minimumVersion();
    final verified = await _verifier.verify(
      envelopeJson,
      accountId: accountId,
      deviceId: deviceId,
      minimumVersion: floor,
      now: now,
    );
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
    final nodes = bundle.payload['nodes'] as List;
    for (final item in nodes) {
      final node = item as Map<String, dynamic>;
      if (node['id'] == nodeId) {
        return const CredentialBox().open(
          encoded: node['encrypted_credentials'] as String,
          deviceSeed: deviceSeed,
          context: CredentialContext(
            accountId: accountId,
            deviceId: deviceId,
            nodeId: nodeId,
            version: bundle.version,
          ),
        );
      }
    }
    throw const BundleException('Node is not in the saved configuration');
  }

  Future<void> clear() async {
    await _store.delete(_bundleKey);
    await _store.delete(_versionKey);
  }
}
