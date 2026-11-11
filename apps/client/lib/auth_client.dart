import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:oidc/oidc.dart';

import 'configuration_vault.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => 'AuthException: $message';
}

abstract class OidcSession {
  Future<void> initialize();
  bool get hasUser;
  Future<bool> signIn();
  Future<String?> accessToken({bool forceRefresh = false});
  Future<void> revokeRefreshToken();
  Future<void> forgetUser();
}

class KeycloakSession implements OidcSession {
  KeycloakSession(this.manager);
  final OidcUserManager manager;

  @override
  Future<void> initialize() => manager.init();
  @override
  bool get hasUser => manager.currentUser != null;
  @override
  Future<bool> signIn() async =>
      await manager.loginAuthorizationCodeFlow() != null;
  @override
  Future<String?> accessToken({bool forceRefresh = false}) =>
      manager.getAccessToken(forceRefresh: forceRefresh);
  @override
  Future<void> revokeRefreshToken() => manager.revokeRefreshToken();
  @override
  Future<void> forgetUser() => manager.forgetUser();
}

class SessionTokens {
  const SessionTokens({
    required this.accountId,
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  final String accountId;
  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  factory SessionTokens.fromJson(Object? input) {
    if (input is! Map<String, dynamic>) {
      throw const AuthException('Invalid session response');
    }
    final accountId = input['account_id'];
    final access = input['access_token'];
    final refresh = input['refresh_token'];
    final accessExpiry = input['access_expires_at'];
    final refreshExpiry = input['refresh_expires_at'];
    if (accountId is! String ||
        accountId.isEmpty ||
        access is! String ||
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
      accountId: accountId,
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
    OidcSession? oidcSession,
  }) : _baseUri = _validateBaseUri(baseUri),
       _http = httpClient,
       _store = secureStore,
       _oidc = oidcSession;

  static const _refreshKey = 'nona.refresh_token.v1';
  static const _usernameKey = 'nona.username.v1';

  final Uri _baseUri;
  final http.Client _http;
  final SecureStringStore _store;
  final OidcSession? _oidc;
  SessionTokens? _tokens;
  String? _oidcAccountId;
  bool _oidcInitialized = false;
  String? _username;
  String? _vpnAccessStatus;

  bool get signedIn =>
      _oidc == null ? _tokens != null : _oidcAccountId != null && _oidc.hasUser;
  String? get accountId =>
      _oidc == null ? _tokens?.accountId : (signedIn ? _oidcAccountId : null);
  String? get username => _username;
  String? get vpnAccessStatus => _vpnAccessStatus;

  String get _deviceSeedKey {
    final identity = _oidc == null
        ? _username?.trim().toLowerCase()
        : _oidcAccountId;
    if (!signedIn || identity == null || identity.isEmpty) {
      throw const AuthException('Sign in required');
    }
    return 'nona.device_seed.v1.$identity';
  }

  /// Returns the device's local X25519 seed for a single in-memory decrypt.
  /// Callers must clear the returned list immediately after use.
  Future<List<int>> readDeviceSeed() async {
    final encoded = await _store.read(_deviceSeedKey);
    if (encoded == null) throw const AuthException('Device key is missing');
    try {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      if (bytes.length == 32 &&
          base64UrlEncode(bytes).replaceAll('=', '') == encoded) {
        return bytes;
      }
    } on FormatException {
      // Treat corrupt secure storage exactly like a missing key.
    }
    throw const AuthException('Invalid saved device key');
  }

  Future<void> _initOidc() async {
    if (_oidcInitialized) return;
    await _oidc!.initialize();
    _oidcInitialized = true;
  }

  Future<void> _loadOidcAccount() async {
    final (status, body) = await _authorizedRequest('GET', '/v1/account');
    if (status == 401) {
      _vpnAccessStatus = 'deleting';
      throw const AuthException('Account unavailable');
    }
    if (status != 200) {
      throw const AuthException('Could not load Keycloak account');
    }
    try {
      final account = jsonDecode(body);
      if (account is! Map<String, dynamic> ||
          account['account_id'] is! String ||
          (account['account_id'] as String).isEmpty ||
          account['username'] is! String ||
          !const [
            'pending',
            'approved',
            'revoking',
            'denied',
            'deleting',
          ].contains(account['vpn_access'])) {
        throw const AuthException('Invalid Keycloak account');
      }
      _oidcAccountId = account['account_id'] as String;
      _username = account['username'] as String;
      _vpnAccessStatus = account['vpn_access'] as String;
    } on FormatException {
      throw const AuthException('Invalid Keycloak account');
    }
  }

  Future<void> refreshAccountStatus() async {
    if (_oidc != null && signedIn) await _loadOidcAccount();
  }

  Future<void> loginWithKeycloak() async {
    if (_oidc == null) throw const AuthException('Keycloak is not configured');
    await _initOidc();
    if (!await _oidc.signIn()) throw const AuthException('Sign in cancelled');
    await _loadOidcAccount();
  }

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
    int maxResponseBytes = 8192,
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
      if (bytes.length + chunk.length > maxResponseBytes) {
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

  Future<(int, String)> _authorizedRequest(
    String method,
    String path, {
    Object? body,
    int maxResponseBytes = 8192,
  }) async {
    if (_oidc != null) {
      final access = await _oidc.accessToken();
      if (access == null) throw const AuthException('Sign in required');
      var response = await _request(
        method,
        path,
        body: body,
        accessToken: access,
        maxResponseBytes: maxResponseBytes,
      );
      if (response.$1 == 401) {
        final fresh = await _oidc.accessToken(forceRefresh: true);
        if (fresh == null) throw const AuthException('Sign in required');
        response = await _request(
          method,
          path,
          body: body,
          accessToken: fresh,
          maxResponseBytes: maxResponseBytes,
        );
      }
      return response;
    }
    var access = _tokens?.accessToken;
    if (access == null) throw const AuthException('Sign in required');
    var response = await _request(
      method,
      path,
      body: body,
      accessToken: access,
      maxResponseBytes: maxResponseBytes,
    );
    if (response.$1 != 401) return response;
    if (!await restore()) throw const AuthException('Sign in required');
    access = _tokens?.accessToken;
    if (access == null) throw const AuthException('Sign in required');
    response = await _request(
      method,
      path,
      body: body,
      accessToken: access,
      maxResponseBytes: maxResponseBytes,
    );
    return response;
  }

  /// Returns null when no update has been issued to this device yet. The
  /// caller must verify the returned signature before saving or using it.
  Future<String?> fetchConfiguration(String deviceId) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(deviceId)) {
      throw const AuthException('Invalid device ID');
    }
    final (status, body) = await _authorizedRequest(
      'GET',
      '/v1/devices/$deviceId/configuration',
      maxResponseBytes: 1500000,
    );
    if (status == 404) return null;
    if (status == 401) {
      _vpnAccessStatus = 'deleting';
      throw const AuthException('Account unavailable');
    }
    if (status != 200) {
      throw const AuthException('Could not load configuration');
    }
    return body;
  }

  /// Saves an account-specific X25519 seed locally and sends only its public
  /// key. Rechecking the server list makes a lost POST response safe to retry.
  Future<String> ensureDeviceRegistered(String label) async {
    final keyName = _deviceSeedKey;
    final algorithm = X25519();
    var encodedSeed = await _store.read(keyName);
    if (encodedSeed == null) {
      final generated = await algorithm.newKeyPair();
      encodedSeed = base64UrlEncode(await generated.extractPrivateKeyBytes())
          .replaceAll('=', '');
      await _store.write(keyName, encodedSeed);
    }
    Future<String> publicKey(String seed) async {
      late final List<int> bytes;
      try {
        bytes = base64Url.decode(base64Url.normalize(seed));
      } on FormatException {
        throw const AuthException('Invalid saved device key');
      }
      if (bytes.length != 32) {
        throw const AuthException('Invalid saved device key');
      }
      final pair = await algorithm.newKeyPairFromSeed(bytes);
      return base64UrlEncode((await pair.extractPublicKey()).bytes)
          .replaceAll('=', '');
    }

    var public = await publicKey(encodedSeed);
    final (listStatus, listBody) = await _authorizedRequest(
      'GET',
      '/v1/devices',
    );
    if (listStatus != 200) {
      throw const AuthException('Could not load devices');
    }
    late final Object? parsed;
    try {
      parsed = jsonDecode(listBody);
    } on FormatException {
      throw const AuthException('Invalid device response');
    }
    if (parsed is! List) {
      throw const AuthException('Invalid device response');
    }
    for (final item in parsed) {
      if (item is! Map<String, dynamic>) {
        throw const AuthException('Invalid device response');
      }
      if (item['public_key'] == public) {
        if (item['revoked_at'] == null && item['id'] is String) {
          return item['id'] as String;
        }
        final replacement = await algorithm.newKeyPair();
        encodedSeed = base64UrlEncode(
          await replacement.extractPrivateKeyBytes(),
        ).replaceAll('=', '');
        await _store.write(keyName, encodedSeed);
        public = await publicKey(encodedSeed);
        break;
      }
    }
    final (status, responseBody) = await _authorizedRequest(
      'POST',
      '/v1/devices',
      body: {'label': label, 'public_key': public},
    );
    if (status == 409) throw const AuthException('Device limit or duplicate');
    if (status != 201) throw const AuthException('Could not register device');
    try {
      final device = jsonDecode(responseBody);
      if (device is Map<String, dynamic> &&
          device['id'] is String &&
          device['public_key'] == public) {
        return device['id'] as String;
      }
    } on FormatException {
      // The seed is retained for recovery through GET on the next attempt.
    }
    throw const AuthException('Invalid device response');
  }

  Future<void> login(String username, String password) async {
    if (_oidc != null) throw const AuthException('Use Keycloak sign in');
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
    if (_oidc != null) {
      await _initOidc();
      if (!_oidc.hasUser) return false;
      await _loadOidcAccount();
      return true;
    }
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
    if (_oidc != null) {
      await _initOidc();
      await _oidc.revokeRefreshToken();
      await _oidc.forgetUser();
      _oidcAccountId = null;
      _username = null;
      _vpnAccessStatus = null;
      return;
    }
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
