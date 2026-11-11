import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config_bundle.dart';
import 'credential_box.dart';
import 'node_access.dart';

abstract interface class SecureStringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class ProtectedStorageException implements Exception {
  const ProtectedStorageException();
}

/// Uses the platform's protected app storage. Access by a future VPN process
/// or Apple Packet Tunnel extension needs explicit native configuration.
class PlatformSecureStringStore implements SecureStringStore {
  PlatformSecureStringStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          (Platform.isMacOS
              ? const FlutterSecureStorage(
                  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
                )
              : const FlutterSecureStorage());

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      throw const ProtectedStorageException();
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException {
      throw const ProtectedStorageException();
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException {
      throw const ProtectedStorageException();
    }
  }
}

/// Stores one device's verified update. Writing the version floor first means
/// an interrupted update fails closed: the older bundle cannot be reloaded.
class ConfigurationVault {
  ConfigurationVault(this._store, this._verifier);

  static int _storageGeneration = 0;

  static const _bundleKey = 'nona.active_bundle.v1';
  static const _versionKey = 'nona.minimum_bundle_version.v1';
  static const _identityKey = 'nona.bundle_identity.v1';

  final SecureStringStore _store;
  final BundleVerifier _verifier;
  bool _identityLoaded = false;
  String? _savedIdentity;
  bool _versionLoaded = false;
  int? _savedVersion;
  bool _bundleLoaded = false;
  String? _savedEnvelope;
  int _cacheGeneration = _storageGeneration;

  void _ensureCurrentCache() {
    if (_cacheGeneration == _storageGeneration) return;
    _invalidateCache();
    _cacheGeneration = _storageGeneration;
  }

  String _identity(String accountId, String deviceId) =>
      jsonEncode([accountId, deviceId]);

  Future<String?> _storedIdentity() async {
    _ensureCurrentCache();
    if (!_identityLoaded) {
      _savedIdentity = await _store.read(_identityKey);
      _identityLoaded = true;
    }
    return _savedIdentity;
  }

  Future<String?> _storedEnvelope() async {
    _ensureCurrentCache();
    if (!_bundleLoaded) {
      _savedEnvelope = await _store.read(_bundleKey);
      _bundleLoaded = true;
    }
    return _savedEnvelope;
  }

  void _invalidateCache() {
    _identityLoaded = false;
    _savedIdentity = null;
    _versionLoaded = false;
    _savedVersion = null;
    _bundleLoaded = false;
    _savedEnvelope = null;
  }

  Future<int> _minimumVersion() async {
    _ensureCurrentCache();
    if (_versionLoaded) return _savedVersion!;
    final text = await _store.read(_versionKey);
    if (text == null) {
      _savedVersion = 0;
      _versionLoaded = true;
      return 0;
    }
    final value = int.tryParse(text);
    if (value == null || value < 0) {
      throw const BundleException('Invalid saved version floor');
    }
    _savedVersion = value;
    _versionLoaded = true;
    return value;
  }

  Future<VerifiedBundle> accept(
    String envelopeJson, {
    required String accountId,
    required String deviceId,
    required DateTime now,
  }) async {
    final identity = _identity(accountId, deviceId);
    if (await _storedIdentity() != identity) {
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
    if (await _storedEnvelope() == envelopeJson && floor >= verified.version) {
      return verified;
    }
    _storageGeneration++;
    _cacheGeneration = _storageGeneration;
    try {
      await _store.write(_identityKey, identity);
      if (verified.version > floor) {
        await _store.write(_versionKey, verified.version.toString());
      }
      await _store.write(_bundleKey, envelopeJson);
    } catch (_) {
      _invalidateCache();
      rethrow;
    }
    _savedIdentity = identity;
    _identityLoaded = true;
    _savedVersion = verified.version > floor ? verified.version : floor;
    _versionLoaded = true;
    _savedEnvelope = envelopeJson;
    _bundleLoaded = true;
    return verified;
  }

  Future<VerifiedBundle?> load({
    required String accountId,
    required String deviceId,
    required DateTime now,
  }) async {
    if (await _storedIdentity() != _identity(accountId, deviceId)) {
      return null;
    }
    final floor = await _minimumVersion();
    final envelopeJson = await _storedEnvelope();
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
    _storageGeneration++;
    _cacheGeneration = _storageGeneration;
    _invalidateCache();
    await _store.delete(_bundleKey);
    await _store.delete(_versionKey);
    await _store.delete(_identityKey);
    _savedIdentity = null;
    _identityLoaded = true;
    _savedVersion = 0;
    _versionLoaded = true;
    _savedEnvelope = null;
    _bundleLoaded = true;
  }
}
