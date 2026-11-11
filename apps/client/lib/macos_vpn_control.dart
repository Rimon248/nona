import 'dart:io';

import 'package:flutter/services.dart';

/// Talks to the native macOS host, which asks for administrator permission
/// before starting Xray TUN or changing system DNS settings.
class MacOSVpnControl {
  MacOSVpnControl._();

  static final MacOSVpnControl instance = MacOSVpnControl._();
  static const _channel = MethodChannel('nona.macos_vpn');

  Future<bool> connect(String configJson) async {
    final started = await _channel.invokeMethod<bool>('connect', {
      'config': configJson,
    });
    if (started != true) return false;
    try {
      await measureLatency();
      return true;
    } catch (_) {
      await stop();
      return false;
    }
  }

  Future<String> status() async =>
      await _channel.invokeMethod<String>('status') ?? 'error';

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<int> measureLatency() async {
    if (await status() != 'connected') {
      throw StateError('VPN is not connected');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final watch = Stopwatch()..start();
    try {
      final request = await client
          .getUrl(Uri.https('cp.cloudflare.com', '/generate_204'))
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw StateError('VPN connectivity check failed');
      }
      watch.stop();
      return watch.elapsedMilliseconds.clamp(1, 60000).toInt();
    } finally {
      client.close(force: true);
    }
  }
}
