import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/node_access.dart';

void main() {
  final valid = {
    'schema_version': 1,
    'vless_reality': {
      'host': 'node.example.invalid',
      'port': 8443,
      'user_id': '00000000-0000-4000-8000-000000000001',
      'server_name': 'front.example.invalid',
      'reality_password': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      'short_id': 'a1b2c3d4',
      'flow': 'xtls-rprx-vision',
    },
    'hysteria2': {
      'host': 'node.example.invalid',
      'port': 443,
      'auth': 'fictional-test-password',
      'server_name': 'node.example.invalid',
      'obfs_password': 'fictional-salamander-password',
    },
  };

  List<int> encoded(Map<String, Object?> document) =>
      utf8.encode(jsonEncode(document));

  test('decryptable document produces both native profiles', () {
    final access = NodeAccess.parse(
      encoded(valid),
      endpoint: 'node.example.invalid',
      transports: ['vless-reality', 'hysteria2'],
    );
    expect(access.vlessReality!.port, 8443);
    expect(access.hysteria2!.port, 443);
    expect(
      (access.hysteria2!.config(localSocksPort: 10809)['obfs'] as Map)['type'],
      'salamander',
    );
    expect(
      access.vlessReality!.config(localSocksPort: 10808)['outbounds'],
      isNotEmpty,
    );
  });

  test('rejects transport or endpoint substitution', () {
    expect(
      () => NodeAccess.parse(
        encoded(valid),
        endpoint: 'other.example.invalid',
        transports: ['vless-reality', 'hysteria2'],
      ),
      throwsA(isA<NodeAccessException>()),
    );
    expect(
      () => NodeAccess.parse(
        encoded(valid),
        endpoint: 'node.example.invalid',
        transports: ['vless-reality'],
      ),
      throwsA(isA<NodeAccessException>()),
    );
  });

  test('rejects unknown fields and malformed credentials', () {
    expect(
      () => NodeAccess.parse(
        encoded({...valid, 'debug': 'secret'}),
        endpoint: 'node.example.invalid',
        transports: ['vless-reality', 'hysteria2'],
      ),
      throwsA(isA<NodeAccessException>()),
    );
    final broken = Map<String, Object?>.from(valid);
    broken['hysteria2'] = {
      'host': 'node.example.invalid',
      'port': 443,
      'auth': '',
      'server_name': 'node.example.invalid',
      'obfs_password': 'fictional-salamander-password',
    };
    expect(
      () => NodeAccess.parse(
        encoded(broken),
        endpoint: 'node.example.invalid',
        transports: ['vless-reality', 'hysteria2'],
      ),
      throwsA(isA<NodeAccessException>()),
    );
  });
}
