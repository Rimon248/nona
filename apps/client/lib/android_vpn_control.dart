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
    final allowed = await _channel.invokeMethod<bool>('prepare') ?? false;
    if (!allowed) return false;
    await _channel.invokeMethod<void>('start', {
      'config': profile.configJson(localSocksPort: 10808),
    });
    return true;
  }

  Future<String> status() async =>
      await _channel.invokeMethod<String>('status') ?? 'error';

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
