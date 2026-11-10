import 'package:flutter/services.dart';

import 'engine_profiles.dart';

/// Android-only bridge. The UI asks for permission only after a verified,
/// decrypted device profile is available and the user starts a connection.
class AndroidVpnControl {
  AndroidVpnControl([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('nona.vpn');

  final MethodChannel _channel;

  /// Returns false if the user declines Android's system VPN consent.
  Future<bool> connect(VlessRealityProfile profile) async {
    return _connect(profile.configJson(localSocksPort: 10808));
  }

  Future<bool> connectHysteria(Hysteria2Profile profile) async {
    return _connect(profile.xrayConfigJson(localSocksPort: 10808));
  }

  Future<bool> _connect(String config) async {
    final allowed = await _channel.invokeMethod<bool>('prepare') ?? false;
    if (!allowed) return false;
    await _channel.invokeMethod<void>('start', {'config': config});
    return true;
  }

  Future<String> status() async =>
      await _channel.invokeMethod<String>('status') ?? 'error';

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
