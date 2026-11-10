import 'dart:convert';

import 'engine_profiles.dart';

class NodeAccessException implements Exception {
  const NodeAccessException(this.message);
  final String message;

  @override
  String toString() => 'NodeAccessException: $message';
}

/// Decrypted credentials exist only while the selected node is in use.
/// The signed bundle declares the endpoint and available transports; both
/// must agree with the encrypted document before a native core sees it.
class NodeAccess {
  const NodeAccess({this.vlessReality, this.hysteria2});

  final VlessRealityProfile? vlessReality;
  final Hysteria2Profile? hysteria2;

  static NodeAccess parse(
    List<int> plaintext, {
    required String endpoint,
    required List<String> transports,
  }) {
    if (plaintext.isEmpty || plaintext.length > 4096) {
      throw const NodeAccessException('Invalid credential document size');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(plaintext));
    } catch (_) {
      throw const NodeAccessException('Invalid credential document');
    }
    if (decoded is! Map<String, dynamic> ||
        !_exactKeys(decoded, {
          'schema_version',
          'vless_reality',
          'hysteria2',
        }) ||
        decoded['schema_version'] != 2) {
      throw const NodeAccessException('Unsupported credential schema');
    }
    final declared = transports.toSet();
    if (declared.length != transports.length ||
        declared.isEmpty ||
        declared.difference({'vless-reality', 'hysteria2'}).isNotEmpty ||
        declared.contains('vless-reality') !=
            (decoded['vless_reality'] != null) ||
        declared.contains('hysteria2') != (decoded['hysteria2'] != null)) {
      throw const NodeAccessException('Credential transports do not match');
    }
    try {
      final vless = decoded['vless_reality'];
      final hysteria = decoded['hysteria2'];
      VlessRealityProfile? vlessProfile;
      Hysteria2Profile? hysteriaProfile;
      if (vless != null) {
        if (vless is! Map<String, dynamic> ||
            !_exactKeys(vless, {
              'host',
              'port',
              'user_id',
              'server_name',
              'reality_password',
              'encryption',
              'short_id',
              'flow',
            }) ||
            vless['host'] != endpoint) {
          throw const NodeAccessException('Invalid VLESS credentials');
        }
        vlessProfile = VlessRealityProfile(
          host: vless['host'] as String,
          port: vless['port'] as int,
          userId: vless['user_id'] as String,
          serverName: vless['server_name'] as String,
          realityPassword: vless['reality_password'] as String,
          encryption: vless['encryption'] as String,
          shortId: vless['short_id'] as String,
          flow: vless['flow'] as String,
        );
      }
      if (hysteria != null) {
        if (hysteria is! Map<String, dynamic> ||
            !_exactKeys(hysteria, {
              'host',
              'port',
              'auth',
              'server_name',
              'obfs_password',
            }) ||
            hysteria['host'] != endpoint) {
          throw const NodeAccessException('Invalid Hysteria2 credentials');
        }
        hysteriaProfile = Hysteria2Profile(
          host: hysteria['host'] as String,
          port: hysteria['port'] as int,
          auth: hysteria['auth'] as String,
          serverName: hysteria['server_name'] as String,
          salamanderPassword: hysteria['obfs_password'] as String?,
        );
      }
      return NodeAccess(vlessReality: vlessProfile, hysteria2: hysteriaProfile);
    } on NodeAccessException {
      rethrow;
    } catch (_) {
      throw const NodeAccessException('Invalid credential fields');
    }
  }
}

bool _exactKeys(Map<String, dynamic> value, Set<String> keys) =>
    value.keys.toSet().length == keys.length &&
    value.keys.toSet().containsAll(keys);
