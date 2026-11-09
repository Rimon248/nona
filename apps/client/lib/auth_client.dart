import 'dart:convert';

import 'package:http/http.dart' as http;

import 'configuration_vault.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => 'AuthException: $message';
}

class SessionTokens {
  const SessionTokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  factory SessionTokens.fromJson(Object? input) {
    if (input is! Map<String, dynamic>) {
      throw const AuthException('Invalid session response');
    }
    final access = input['access_token'];
    final refresh = input['refresh_token'];
    final accessExpiry = input['access_expires_at'];
    final refreshExpiry = input['refresh_expires_at'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        accessExpiry is! String ||
        refreshExpiry is! String) {
      throw const AuthException('Invalid session response');
    }
    final accessTime = DateTime.tryParse(accessExpiry)?.toUtc();
    final refreshTime = DateTime.tryParse(refreshExpiry)?.toUtc();
    if (accessTime == null ||
        refreshTime == null ||
        refreshTime.isBefore(accessTime)) {
      throw const AuthException('Invalid session expiry');
    }
    return SessionTokens(
      accessToken: access,
      accessExpiresAt: accessTime,
      refreshToken: refresh,
      refreshExpiresAt: refreshTime,
    );
  }
}

/// Handles the control API only. It never receives or controls VPN packets.
/// The access token remains in memory; the refresh token is stored by the OS.
class AuthClient {
  AuthClient({
    required Uri baseUri,
    required http.Client httpClient,
    required SecureStringStore secureStore,
  }) : _baseUri = _validateBaseUri(baseUri),
       _http = httpClient,
       _store = secureStore;

  static const _refreshKey = 'nona.refresh_token.v1';
  static const _usernameKey = 'nona.username.v1';

  final Uri _baseUri;
  final http.Client _http;
  final SecureStringStore _store;
  SessionTokens? _tokens;
  String? _username;

  bool get signedIn => _tokens != null;
  String? get username => _username;

  static Uri _validateBaseUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(uri, 'baseUri', 'A HTTPS origin is required');
    }
    return uri;
  }

  Uri _path(String path) => _baseUri.replace(path: path);

  Future<(int, String)> _request(
    String method,
    String path, {
    Object? body,
    String? accessToken,
  }) async {
    final request = http.Request(method, _path(path))..followRedirects = false;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    final streamed = await _http
        .send(request)
        .timeout(const Duration(seconds: 10));
    final bytes = <int>[];
    await for (final chunk in streamed.stream.timeout(
      const Duration(seconds: 10),
    )) {
      if (bytes.length + chunk.length > 8192) {
        throw const AuthException('Oversized server response');
      }
      bytes.addAll(chunk);
    }
    return (streamed.statusCode, utf8.decode(bytes));
  }

  Future<SessionTokens> _readTokens(int status, String body) async {
    if (status == 401 || status == 429) {
      throw AuthException(
        status == 401 ? 'Invalid credentials' : 'Too many attempts',
      );
    }
    if (status != 200) {
      throw const AuthException('Account server is unavailable');
    }
    try {
      return SessionTokens.fromJson(jsonDecode(body));
    } on FormatException {
      throw const AuthException('Invalid session response');
    }
  }

  Future<void> login(String username, String password) async {
    final (status, body) = await _request(
      'POST',
      '/v1/sessions',
      body: {'username': username, 'password': password},
    );
    final received = await _readTokens(status, body);
    await _store.write(_refreshKey, received.refreshToken);
    await _store.write(_usernameKey, username);
    _tokens = received;
    _username = username;
  }

  /// Returns false when there is no usable saved session. Network errors are
  /// surfaced so the UI can distinguish offline state from signed-out state.
  Future<bool> restore() async {
    final saved = await _store.read(_refreshKey);
    if (saved == null) return false;
    try {
      final (status, body) = await _request(
        'POST',
        '/v1/sessions/refresh',
        body: {'refresh_token': saved},
      );
      final received = await _readTokens(status, body);
      await _store.write(_refreshKey, received.refreshToken);
      _tokens = received;
      _username = await _store.read(_usernameKey);
      return true;
    } on AuthException catch (error) {
      if (error.message == 'Invalid credentials') {
        await _store.delete(_refreshKey);
        await _store.delete(_usernameKey);
        _tokens = null;
        _username = null;
        return false;
      }
      rethrow;
    }
  }

  /// A failed server request keeps the local session for a later retry. The
  /// app must not claim that server-side access was revoked in that case.
  Future<void> logout() async {
    var tokens = _tokens;
    if (tokens == null) return;
    var (status, _) = await _request(
      'DELETE',
      '/v1/sessions/current',
      accessToken: tokens.accessToken,
    );
    if (status == 401) {
      if (!await restore()) return;
      tokens = _tokens;
      if (tokens == null) return;
      (status, _) = await _request(
        'DELETE',
        '/v1/sessions/current',
        accessToken: tokens.accessToken,
      );
    }
    if (status != 204) {
      throw const AuthException('Could not revoke session');
    }
    await _store.delete(_refreshKey);
    await _store.delete(_usernameKey);
    _tokens = null;
    _username = null;
  }
}
