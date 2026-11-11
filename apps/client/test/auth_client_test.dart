import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nona_client/auth_client.dart';
import 'package:nona_client/configuration_vault.dart';

class MemorySecureStore implements SecureStringStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FakeOidcSession implements OidcSession {
  bool signedIn = false;
  bool revoked = false;
  int refreshes = 0;

  @override
  Future<void> initialize() async {}
  @override
  bool get hasUser => signedIn;
  @override
  Future<bool> signIn() async {
    signedIn = true;
    return true;
  }

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async {
    if (forceRefresh) refreshes++;
    return signedIn ? 'keycloak-access' : null;
  }

  @override
  Future<void> revokeRefreshToken() async => revoked = true;
  @override
  Future<void> forgetUser() async => signedIn = false;
}

String tokenResponse(String access, String refresh) => jsonEncode({
  'account_id': 'account-a',
  'access_token': access,
  'access_expires_at': '2026-11-09T12:15:00Z',
  'refresh_token': refresh,
  'refresh_expires_at': '2026-12-09T12:00:00Z',
});

void main() {
  test('a deleted Keycloak account cannot keep its prior approval', () async {
    final oidc = FakeOidcSession();
    var deleted = false;
    final auth = AuthClient(
      baseUri: Uri.parse('https://nona.example.invalid'),
      secureStore: MemorySecureStore(),
      oidcSession: oidc,
      httpClient: MockClient((request) async {
        if (deleted) return http.Response('', 401);
        return http.Response(
          '{"account_id":"account-k","username":"user","vpn_access":"approved"}',
          200,
        );
      }),
    );
    await auth.loginWithKeycloak();
    expect(auth.vpnAccessStatus, 'approved');
    deleted = true;
    await expectLater(
      auth.refreshAccountStatus(),
      throwsA(isA<AuthException>()),
    );
    expect(oidc.refreshes, 1);
    expect(auth.vpnAccessStatus, 'deleting');
  });

  test(
    'Keycloak login uses its bearer token and local account mapping',
    () async {
      final oidc = FakeOidcSession();
      final store = MemorySecureStore();
      final paths = <String>[];
      final auth = AuthClient(
        baseUri: Uri.parse('https://nona.example.invalid'),
        secureStore: store,
        oidcSession: oidc,
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          expect(request.headers['authorization'], 'Bearer keycloak-access');
          if (request.url.path == '/v1/account') {
            return http.Response(
              '{"account_id":"account-k","username":"roman","provider":"keycloak","vpn_access":"pending"}',
              200,
            );
          }
          if (request.url.path == '/v1/devices' && request.method == 'GET') {
            return http.Response('[]', 200);
          }
          if (request.url.path == '/v1/devices' && request.method == 'POST') {
            final key = jsonDecode(request.body)['public_key'];
            return http.Response(
              jsonEncode({'id': 'device-k', 'public_key': key}),
              201,
            );
          }
          return http.Response('', 404);
        }),
      );
      expect(await auth.restore(), isFalse);
      await auth.loginWithKeycloak();
      expect(auth.accountId, 'account-k');
      expect(auth.username, 'roman');
      expect(auth.vpnAccessStatus, 'pending');
      expect(await auth.ensureDeviceRegistered('Android'), 'device-k');
      expect(store.values.containsKey('nona.device_seed.v1.account-k'), isTrue);
      expect(paths, isNot(contains('/v1/sessions')));
      await auth.logout();
      expect(oidc.revoked, isTrue);
      expect(auth.signedIn, isFalse);
    },
  );

  test('rejects a non-HTTPS account server', () {
    expect(
      () => AuthClient(
        baseUri: Uri.parse('http://example.invalid'),
        httpClient: MockClient((_) async => http.Response('', 200)),
        secureStore: MemorySecureStore(),
      ),
      throwsArgumentError,
    );
  });

  test('logs in, rotates a saved refresh token, and logs out', () async {
    final store = MemorySecureStore();
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      if (request.url.path == '/v1/sessions') {
        return http.Response(tokenResponse('access-1', 'refresh-1'), 200);
      }
      if (request.url.path == '/v1/sessions/refresh') {
        expect(jsonDecode(request.body)['refresh_token'], 'refresh-1');
        return http.Response(tokenResponse('access-2', 'refresh-2'), 200);
      }
      if (request.url.path == '/v1/sessions/current') {
        expect(request.headers['authorization'], 'Bearer access-2');
        return http.Response('', 204);
      }
      return http.Response('', 404);
    });
    final auth = AuthClient(
      baseUri: Uri.parse('https://accounts.example.invalid'),
      httpClient: client,
      secureStore: store,
    );
    await auth.login('alice', 'a long test password');
    expect(auth.signedIn, isTrue);
    expect(auth.accountId, 'account-a');
    expect(store.values['nona.refresh_token.v1'], 'refresh-1');
    expect(seen.first.url.scheme, 'https');
    expect(seen.first.followRedirects, isFalse);

    final restored = AuthClient(
      baseUri: Uri.parse('https://accounts.example.invalid'),
      httpClient: client,
      secureStore: store,
    );
    expect(await restored.restore(), isTrue);
    expect(restored.accountId, 'account-a');
    expect(store.values['nona.refresh_token.v1'], 'refresh-2');
    await restored.logout();
    expect(restored.signedIn, isFalse);
    expect(store.values, isEmpty);
  });

  test('fetches only the registered device configuration', () async {
    const deviceId = '0123456789abcdef0123456789abcdef';
    final client = MockClient((request) async {
      if (request.url.path == '/v1/sessions') {
        return http.Response(tokenResponse('access-1', 'refresh-1'), 200);
      }
      expect(request.headers['authorization'], 'Bearer access-1');
      expect(request.url.path, '/v1/devices/$deviceId/configuration');
      return http.Response('{"key_id":"test"}', 200);
    });
    final auth = AuthClient(
      baseUri: Uri.parse('https://accounts.example.invalid'),
      httpClient: client,
      secureStore: MemorySecureStore(),
    );
    await auth.login('alice', 'a long test password');
    expect(await auth.fetchConfiguration(deviceId), '{"key_id":"test"}');
    await expectLater(
      auth.fetchConfiguration('../another-device'),
      throwsA(isA<AuthException>()),
    );
  });

  test('does not send credentials to a redirect destination', () async {
    final auth = AuthClient(
      baseUri: Uri.parse('https://accounts.example.invalid'),
      httpClient: MockClient(
        (_) async => http.Response(
          '',
          307,
          headers: {'location': 'https://other.example.invalid'},
        ),
      ),
      secureStore: MemorySecureStore(),
    );
    await expectLater(
      auth.login('alice', 'a long test password'),
      throwsA(isA<AuthException>()),
    );
  });

  test(
    'device registration recovers after a lost response without a new key',
    () async {
      final store = MemorySecureStore();
      String? registeredPublic;
      var postCount = 0;
      final auth = AuthClient(
        baseUri: Uri.parse('https://accounts.example.invalid'),
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/sessions') {
            return http.Response(tokenResponse('access-1', 'refresh-1'), 200);
          }
          expect(request.headers['authorization'], 'Bearer access-1');
          if (request.url.path == '/v1/devices' && request.method == 'GET') {
            return http.Response(
              jsonEncode(
                registeredPublic == null
                    ? []
                    : [
                        {
                          'id': 'device-1',
                          'public_key': registeredPublic,
                          'revoked_at': null,
                        },
                      ],
              ),
              200,
            );
          }
          if (request.url.path == '/v1/devices' && request.method == 'POST') {
            postCount++;
            registeredPublic = jsonDecode(request.body)['public_key'] as String;
            return http.Response(
              '{',
              201,
            ); // Server committed, response was lost.
          }
          return http.Response('', 404);
        }),
        secureStore: store,
      );
      await auth.login('Alice', 'a long test password');
      await expectLater(
        auth.ensureDeviceRegistered('Android'),
        throwsA(isA<AuthException>()),
      );
      final seed = store.values['nona.device_seed.v1.alice'];
      expect(seed, isNotNull);
      expect(seed, isNot(registeredPublic));
      expect(await auth.ensureDeviceRegistered('Android'), 'device-1');
      expect(store.values['nona.device_seed.v1.alice'], seed);
      expect(postCount, 1);
    },
  );

  test(
    'refreshes an expired access token before revoking the session',
    () async {
      final store = MemorySecureStore();
      var deleteCalls = 0;
      final auth = AuthClient(
        baseUri: Uri.parse('https://accounts.example.invalid'),
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/sessions') {
            return http.Response(
              tokenResponse('old-access', 'old-refresh'),
              200,
            );
          }
          if (request.url.path == '/v1/sessions/refresh') {
            return http.Response(
              tokenResponse('new-access', 'new-refresh'),
              200,
            );
          }
          if (request.url.path == '/v1/sessions/current') {
            deleteCalls++;
            return http.Response('', deleteCalls == 1 ? 401 : 204);
          }
          return http.Response('', 404);
        }),
        secureStore: store,
      );
      await auth.login('alice', 'a long test password');
      await auth.logout();
      expect(deleteCalls, 2);
      expect(auth.signedIn, isFalse);
      expect(store.values, isEmpty);
    },
  );
}
