import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps Nona's macOS secrets in one Keychain item.
///
/// `flutter_secure_storage` normally creates one Keychain item per logical
/// key. Reading OIDC tokens, the device seed, and the saved configuration can
/// therefore cause a separate authorization prompt for each item. This class
/// stores the logical key/value map as one Keychain value and lazily migrates
/// legacy per-key items when they are read.
class MacCompactSecureStorage extends FlutterSecureStorage {
  MacCompactSecureStorage()
    : super(mOptions: const MacOsOptions(usesDataProtectionKeychain: false));

  static const _recordKey = 'nona.protected_store.v1';
  static Future<void> _pendingOperation = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _pendingOperation = _pendingOperation.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<_CompactStoreState> _readState(AppleOptions? options) async {
    final raw = await super.read(key: _recordKey, mOptions: options);
    if (raw == null) return _CompactStoreState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          decoded['checked'] is! List ||
          decoded['values'] is! Map) {
        throw const FormatException();
      }
      final checked = (decoded['checked'] as List).cast<String>().toSet();
      final values = <String, String>{};
      for (final entry in (decoded['values'] as Map).entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException();
        }
        values[entry.key as String] = entry.value as String;
      }
      if (values.keys.any((key) => !checked.contains(key))) {
        throw const FormatException();
      }
      return _CompactStoreState(checked: checked, values: values);
    } on Object {
      throw PlatformException(
        code: 'invalid_nona_secure_store',
        message: 'Защищённое хранилище Ноны повреждено',
      );
    }
  }

  Future<void> _writeState(_CompactStoreState state, AppleOptions? options) =>
      super.write(
        key: _recordKey,
        value: jsonEncode(state.toJson()),
        mOptions: options,
      );

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (key == _recordKey) return super.read(key: key, mOptions: mOptions);
    return _exclusive(() async {
      final state = await _readState(mOptions);
      if (state.checked.contains(key)) return state.values[key];

      // Preserve credentials and device identity saved by older Nona builds.
      final legacy = await super.read(key: key, mOptions: mOptions);
      state.checked.add(key);
      if (legacy != null) state.values[key] = legacy;
      await _writeState(state, mOptions);
      if (legacy != null) {
        await super.delete(key: key, mOptions: mOptions);
      }
      return legacy;
    });
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (key == _recordKey) {
      return super.write(key: key, value: value, mOptions: mOptions);
    }
    if (value == null) return delete(key: key, mOptions: mOptions);
    return _exclusive(() async {
      final state = await _readState(mOptions);
      state.checked.add(key);
      state.values[key] = value;
      await _writeState(state, mOptions);
    });
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (key == _recordKey) return super.delete(key: key, mOptions: mOptions);
    return _exclusive(() async {
      final state = await _readState(mOptions);
      state.checked.add(key);
      state.values.remove(key);
      await _writeState(state, mOptions);
      await super.delete(key: key, mOptions: mOptions);
    });
  }
}

class _CompactStoreState {
  _CompactStoreState({Set<String>? checked, Map<String, String>? values})
    : checked = checked ?? <String>{},
      values = values ?? <String, String>{};

  final Set<String> checked;
  final Map<String, String> values;

  Map<String, Object> toJson() => {
    'version': 1,
    'checked': checked.toList()..sort(),
    'values': values,
  };
}
