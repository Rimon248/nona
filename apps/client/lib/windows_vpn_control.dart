import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _CGoInvokeNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _CGoInvokeDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _CGoFreeNative = Void Function(Pointer<Utf8>);
typedef _CGoFreeDart = void Function(Pointer<Utf8>);

/// Windows desktop bridge to the pinned libXray runtime.
///
/// The Windows app is launched with an explicit UAC prompt because the Xray
/// TUN inbound changes system routes and WFP rules. It never stores the
/// decrypted profile on disk.
class WindowsVpnControl {
  WindowsVpnControl._();

  static final WindowsVpnControl instance = WindowsVpnControl._();

  DynamicLibrary? _library;
  _CGoInvokeDart? _invoke;
  _CGoFreeDart? _free;
  bool _active = false;

  bool get available => Platform.isWindows;

  Future<bool> connect(String configJson) async {
    if (!available) return false;
    if (await status() == 'connected') await stop();
    final response = _request('runXray', {'xrayJson': configJson});
    if (response['success'] != true) {
      throw const WindowsVpnException('Не удалось запустить сетевой туннель');
    }
    _active = true;
    try {
      // Xray applies the TUN routes during startup. Keep the independent
      // latency request as a data-plane check; the website check is reported
      // separately so one blocked probe host cannot reject a live link.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await measureLatency();
      return true;
    } catch (_) {
      await stop();
      return false;
    }
  }

  Future<String> status() async {
    if (!available) return 'idle';
    final response = _request('getXrayState', const {});
    if (response['success'] != true) {
      throw const WindowsVpnException('Не удалось проверить состояние VPN');
    }
    final data = response['data'];
    _active = data is Map && data['running'] == true;
    return _active ? 'connected' : 'idle';
  }

  Future<int> measureLatency() async {
    if (await status() != 'connected') {
      throw const WindowsVpnException('VPN не подключён');
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
        throw const WindowsVpnException('Проверка VPN не прошла');
      }
      watch.stop();
      return watch.elapsedMilliseconds.clamp(1, 60000).toInt();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stop() async {
    if (!available || await status() == 'idle') return;
    final response = _request('stopXray', const {});
    if (response['success'] != true) {
      throw const WindowsVpnException('Не удалось остановить сетевой туннель');
    }
    _active = false;
  }

  Map<String, dynamic> _request(String method, Map<String, Object?> payload) {
    try {
      final library = _library ??= DynamicLibrary.open('libXray.dll');
      final invoke = _invoke ??= library
          .lookupFunction<_CGoInvokeNative, _CGoInvokeDart>('CGoInvoke');
      _free ??= library.lookupFunction<_CGoFreeNative, _CGoFreeDart>('CGoFree');

      final request = jsonEncode({
        'apiVersion': 3,
        'method': method,
        'payload': payload,
      }).toNativeUtf8();
      try {
        final response = invoke(request);
        if (response == nullptr) {
          throw const WindowsVpnException('Ядро VPN не ответило');
        }
        try {
          final decoded = jsonDecode(response.toDartString());
          if (decoded is! Map<String, dynamic>) {
            throw const WindowsVpnException('Некорректный ответ ядра VPN');
          }
          return decoded;
        } finally {
          _free!(response);
        }
      } finally {
        malloc.free(request);
      }
    } on WindowsVpnException {
      rethrow;
    } catch (_) {
      throw const WindowsVpnException('Компонент VPN недоступен');
    }
  }
}

class WindowsVpnException implements Exception {
  const WindowsVpnException(this.message);
  final String message;
}
