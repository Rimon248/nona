import 'dart:io';

import 'package:flutter/services.dart';

import 'engine_profiles.dart';

/// iOS Packet Tunnel bridge. The verified profile is passed only as an
/// ephemeral start option; persistent VPN preferences contain no credentials.
class IosVpnControl {
  IosVpnControl([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('nona.ios.vpn');

  final MethodChannel _channel;

  Future<bool> connectHysteria(Hysteria2Profile profile) =>
      _start(profile.xrayConfigJson(localSocksPort: 10808));

  Future<bool> connect(VlessRealityProfile profile) =>
      _start(profile.configJson(localSocksPort: 10808));

  Future<bool> _start(String config) async {
    await _channel.invokeMethod<void>('start', {'config': config});
    return true;
  }

  Future<String> status() async =>
      await _channel.invokeMethod<String>('status') ?? 'error';

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<int> measureLatency() async {
    if (await status() != 'connected') throw StateError('VPN is not connected');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final watch = Stopwatch()..start();
    try {
      final request = await client
          .getUrl(Uri.https('1.1.1.1', '/'))
          .timeout(const Duration(seconds: 7));
      final response = await request.close().timeout(const Duration(seconds: 7));
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw StateError('VPN traffic check failed');
      }
      if (await status() != 'connected') throw StateError('VPN disconnected');
      return watch.elapsedMilliseconds.clamp(1, 60000);
    } finally {
      client.close(force: true);
    }
  }
}
