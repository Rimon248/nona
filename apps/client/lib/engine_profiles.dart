import 'dart:convert';

/// Configurations for native cores. These contain secrets while in memory:
/// never log, export, or persist their JSON outside protected app storage.
enum NativeCore { xray, hysteria2 }

class EngineProfileException implements Exception {
  const EngineProfileException(this.message);
  final String message;

  @override
  String toString() => 'EngineProfileException: $message';
}

final _hostPattern = RegExp(r'^[a-zA-Z0-9.-]+$');
final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _realityKeyPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
final _shortIdPattern = RegExp(r'^(?:[0-9a-fA-F]{2}){0,8}$');
final _vlessEncryptionPattern = RegExp(
  r'^mlkem768x25519plus\.(?:native|xorpub|random)\.(?:1rtt|0rtt)\.([A-Za-z0-9_-]{43})$',
);

void _checkHost(String host) {
  if (host.isEmpty ||
      host.length > 253 ||
      host.startsWith('.') ||
      host.endsWith('.') ||
      host.contains('..') ||
      !(host.contains(':') ? _validIPv6(host) : _hostPattern.hasMatch(host))) {
    throw const EngineProfileException('Invalid server address');
  }
}

bool _validIPv6(String host) {
  // URI parsing validates the literal without permitting a URI or port here.
  final uri = Uri.tryParse('http://[$host]/');
  return uri != null && uri.host.isNotEmpty && uri.host.contains(':');
}

bool _validRealityKey(String key) {
  if (!_realityKeyPattern.hasMatch(key)) return false;
  try {
    final bytes = base64Url.decode(base64Url.normalize(key));
    return bytes.length == 32 &&
        base64UrlEncode(bytes).replaceAll('=', '') == key;
  } on FormatException {
    return false;
  }
}

bool _validVlessEncryption(String value) {
  final match = _vlessEncryptionPattern.firstMatch(value);
  return match != null && _validRealityKey(match.group(1)!);
}

void _checkPort(int port) {
  if (port < 1 || port > 65535) {
    throw const EngineProfileException('Invalid port');
  }
}

String _hostPort(String host, int port) =>
    '${host.contains(':') ? '[$host]' : host}:$port';

class VlessRealityProfile {
  VlessRealityProfile({
    required this.host,
    required this.port,
    required this.userId,
    required this.serverName,
    required this.realityPassword,
    required this.encryption,
    required this.shortId,
    this.flow = 'xtls-rprx-vision',
  }) {
    _checkHost(host);
    _checkHost(serverName);
    _checkPort(port);
    if (!_uuidPattern.hasMatch(userId) ||
        !_validRealityKey(realityPassword) ||
        !_validVlessEncryption(encryption) ||
        !_shortIdPattern.hasMatch(shortId) ||
        !{'', 'xtls-rprx-vision', 'xtls-rprx-vision-udp443'}.contains(flow)) {
      throw const EngineProfileException('Invalid VLESS REALITY parameters');
    }
  }

  final String host;
  final int port;
  final String userId;
  final String serverName;

  /// Xray's current REALITY `password` field is the server public key.
  final String realityPassword;
  final String encryption;
  final String shortId;
  final String flow;

  NativeCore get core => NativeCore.xray;

  Map<String, Object> config({required int localSocksPort}) {
    _checkPort(localSocksPort);
    return {
      'log': {'loglevel': 'warning', 'access': 'none'},
      'inbounds': [
        {
          'tag': 'local-socks',
          'listen': '127.0.0.1',
          'port': localSocksPort,
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true, 'ip': '127.0.0.1'},
        },
      ],
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'address': host,
            'port': port,
            'id': userId,
            'encryption': encryption,
            if (flow.isNotEmpty) 'flow': flow,
          },
          'streamSettings': {
            'method': 'raw',
            'security': 'reality',
            'realitySettings': {
              'serverName': serverName,
              'fingerprint': 'chrome',
              'password': realityPassword,
              'shortId': shortId,
            },
          },
        },
      ],
    };
  }

  String configJson({required int localSocksPort}) =>
      jsonEncode(config(localSocksPort: localSocksPort));
}

class Hysteria2Profile {
  Hysteria2Profile({
    required this.host,
    required this.port,
    required this.auth,
    required this.serverName,
    this.salamanderPassword,
  }) {
    _checkHost(host);
    _checkHost(serverName);
    _checkPort(port);
    if (auth.isEmpty ||
        auth.length > 1024 ||
        auth.contains('\n') ||
        (salamanderPassword != null &&
            (salamanderPassword!.isEmpty ||
                salamanderPassword!.length > 1024 ||
                salamanderPassword!.contains('\n')))) {
      throw const EngineProfileException('Invalid Hysteria2 authentication');
    }
  }

  final String host;
  final int port;
  final String auth;
  final String serverName;
  final String? salamanderPassword;

  NativeCore get core => NativeCore.hysteria2;

  Map<String, Object> config({required int localSocksPort}) {
    _checkPort(localSocksPort);
    return {
      'server': _hostPort(host, port),
      'auth': auth,
      'tls': {'sni': serverName, 'insecure': false},
      if (salamanderPassword != null)
        'obfs': {
          'type': 'salamander',
          'salamander': {'password': salamanderPassword!},
        },
      'socks5': {'listen': '127.0.0.1:$localSocksPort', 'disableUDP': false},
    };
  }

  String configJson({required int localSocksPort}) =>
      jsonEncode(config(localSocksPort: localSocksPort));

  /// Xray's Hysteria2 transport shares the Android TUN runtime with VLESS.
  Map<String, Object> xrayConfig({required int localSocksPort}) {
    _checkPort(localSocksPort);
    return {
      'log': {'loglevel': 'warning', 'access': 'none'},
      'inbounds': [
        {
          'tag': 'local-socks',
          'listen': '127.0.0.1',
          'port': localSocksPort,
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true, 'ip': '127.0.0.1'},
        },
      ],
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'hysteria',
          'settings': {'version': 2, 'address': host, 'port': port},
          'streamSettings': {
            'method': 'hysteria',
            'hysteriaSettings': {'version': 2, 'auth': auth},
            'security': 'tls',
            'tlsSettings': {
              'serverName': serverName,
              'alpn': ['h3'],
            },
            if (salamanderPassword != null)
              'finalmask': {
                'udp': [
                  {
                    'type': 'salamander',
                    'settings': {'password': salamanderPassword!},
                  },
                ],
              },
          },
        },
      ],
    };
  }

  String xrayConfigJson({required int localSocksPort}) =>
      jsonEncode(xrayConfig(localSocksPort: localSocksPort));
}
