import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/android_vpn_control.dart';
import 'package:nona_client/engine_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nona.vpn.test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  final profile = VlessRealityProfile(
    host: 'node.example.invalid',
    port: 443,
    userId: '00000000-0000-4000-8000-000000000001',
    serverName: 'front.example.invalid',
    realityPassword: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    shortId: 'a1b2c3d4',
  );

  test('declined system consent never submits a profile', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return false;
    });
    expect(await AndroidVpnControl(channel).connect(profile), isFalse);
    expect(methods, ['prepare']);
  });

  test('approved consent submits only the prepared Xray profile', () async {
    String? submitted;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'prepare') return true;
      if (call.method == 'start') {
        submitted = (call.arguments as Map)['config'] as String;
        return null;
      }
      throw MissingPluginException();
    });
    expect(await AndroidVpnControl(channel).connect(profile), isTrue);
    final config = jsonDecode(submitted!) as Map<String, dynamic>;
    expect((config['inbounds'] as List).single['listen'], '127.0.0.1');
    expect((config['outbounds'] as List).single['protocol'], 'vless');
  });
}
