import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/engine_profiles.dart';

void main() {
  test('VLESS REALITY profile keeps transport security enabled', () {
    final profile = VlessRealityProfile(
      host: 'node.example.invalid',
      port: 443,
      userId: '00000000-0000-4000-8000-000000000001',
      serverName: 'front.example.invalid',
      realityPassword: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      shortId: 'a1b2c3d4',
    );
    final config = profile.config(localSocksPort: 10808);
    final outbound = (config['outbounds'] as List).single as Map;
    final stream = outbound['streamSettings'] as Map;
    expect(profile.core, NativeCore.xray);
    expect(stream['security'], 'reality');
    expect(
      (stream['realitySettings'] as Map)['password'],
      profile.realityPassword,
    );
    expect((config['inbounds'] as List).single['listen'], '127.0.0.1');
    expect(
      profile.configJson(localSocksPort: 10808),
      contains('"protocol":"vless"'),
    );
  });

  test('Hysteria2 profile verifies TLS and binds only to loopback', () {
    final profile = Hysteria2Profile(
      host: '2001:db8::1',
      port: 8443,
      auth: 'example-password',
      serverName: 'front.example.invalid',
    );
    final config = profile.config(localSocksPort: 10809);
    expect(profile.core, NativeCore.hysteria2);
    expect(config['server'], '[2001:db8::1]:8443');
    expect((config['tls'] as Map)['insecure'], false);
    expect((config['socks5'] as Map)['listen'], '127.0.0.1:10809');
  });

  test('rejects malformed addresses and REALITY short IDs', () {
    expect(
      () => VlessRealityProfile(
        host: 'https://node.example.invalid',
        port: 443,
        userId: '00000000-0000-4000-8000-000000000001',
        serverName: 'front.example.invalid',
        realityPassword: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        shortId: 'abc',
      ),
      throwsA(isA<EngineProfileException>()),
    );
    expect(
      () => Hysteria2Profile(
        host: 'node.example.invalid',
        port: 0,
        auth: 'example-password',
        serverName: 'front.example.invalid',
      ),
      throwsA(isA<EngineProfileException>()),
    );
  });
}
