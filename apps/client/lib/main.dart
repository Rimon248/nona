import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'internet_routing_screen.dart';
import 'macos_vpn_control.dart';
import 'android_vpn_control.dart';
import 'auth_client.dart';
import 'config_bundle.dart';
import 'configuration_sync.dart';
import 'configuration_vault.dart';
import 'desktop_engine_profile.dart';
import 'engine_profiles.dart';
import 'vpn_action_policy.dart';
import 'windows_vpn_control.dart';

void main() => runApp(const NonaApp());

class NonaApp extends StatelessWidget {
  const NonaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Виртуальный Помощник Нона',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF276A67)),
        scaffoldBackgroundColor: const Color(0xFFF5F7F5),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _apiBaseUrl = String.fromEnvironment('NONA_API_BASE_URL');
  static const _oidcIssuer = String.fromEnvironment(
    'NONA_OIDC_ISSUER',
    defaultValue: 'https://nona.server.basketref.ru/auth/realms/nona',
  );
  static const _configKeyId = String.fromEnvironment('NONA_CONFIG_KEY_ID');
  static const _configVerifyKey = String.fromEnvironment(
    'NONA_CONFIG_VERIFY_KEY_B64',
  );
  http.Client? _http;
  OidcUserManager? _oidc;
  AuthClient? _auth;
  ConfigurationVault? _vault;
  final AndroidVpnControl _androidVpn = AndroidVpnControl();
  final WindowsVpnControl _windowsVpn = WindowsVpnControl.instance;
  final MacOSVpnControl _macVpn = MacOSVpnControl.instance;
  String? _deviceId;
  String? _message;
  String _configurationMessage = 'На этом устройстве пока не сохранены';
  bool _hasUsableConfiguration = false;
  bool _busy = false;
  String _vpnState = 'idle';
  String? _vpnTransport;
  int? _latencyMs;
  bool _measuringLatency = false;
  String? _latencyMessage;
  int _latencyRequestId = 0;
  Timer? _updateTimer;

  static const MethodChannel _trayChannel = MethodChannel('nona.tray');

  bool get _vpnControlsAvailable =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _trayChannel.setMethodCallHandler(_handleTrayCall);
    }
    if (_vpnControlsAvailable) _refreshVpnState();
    if (_apiBaseUrl.isEmpty) return;
    try {
      final issuer = Uri.parse(_oidcIssuer);
      if (issuer.scheme != 'https' ||
          issuer.host != Uri.parse(_apiBaseUrl).host ||
          issuer.hasQuery ||
          issuer.hasFragment) {
        throw const FormatException('Invalid Keycloak issuer');
      }
      _oidc = OidcUserManager.lazy(
        id: 'nona',
        discoveryDocumentUri: issuer.replace(
          path: '${issuer.path}/.well-known/openid-configuration',
        ),
        clientCredentials: const OidcClientAuthentication.none(
          clientId: 'nona-client',
        ),
        store: OidcDefaultStore(
          secureStorageInstance: Platform.isMacOS
              ? const FlutterSecureStorage(
                  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
                )
              : OidcDefaultStore.createHardenedSecureStorage(),
        ),
        settings: OidcUserManagerSettings(
          scope: const ['openid', 'profile', 'email'],
          redirectUri: defaultTargetPlatform == TargetPlatform.windows
              ? Uri.parse('http://127.0.0.1:0')
              : Uri.parse('ru.basketref.nona://oauth2redirect'),
        ),
      );
      _http = http.Client();
      _auth = AuthClient(
        baseUri: Uri.parse(_apiBaseUrl),
        httpClient: _http!,
        secureStore: PlatformSecureStringStore(),
        oidcSession: KeycloakSession(_oidc!),
      );
    } catch (_) {
      _message = 'Некорректный HTTPS-адрес входа';
      return;
    }
    if (_configKeyId.isNotEmpty && _configVerifyKey.isNotEmpty) {
      try {
        final key = base64Url.decode(base64Url.normalize(_configVerifyKey));
        if (key.length != 32 ||
            base64UrlEncode(key).replaceAll('=', '') != _configVerifyKey) {
          throw const FormatException('Invalid configuration signing key');
        }
        _vault = ConfigurationVault(
          PlatformSecureStringStore(),
          BundleVerifier({_configKeyId: key}),
        );
      } catch (_) {
        _configurationMessage = 'Неверный ключ проверки обновлений';
      }
    }
    _restore();
    _updateTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted && !_busy && _auth?.signedIn == true && _deviceId != null) {
        _checkUpdates();
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _trayChannel.setMethodCallHandler(null);
    }
    _oidc?.dispose();
    _http?.close();
    super.dispose();
  }

  Future<void> _handleTrayCall(MethodCall call) async {
    if (call.method != 'requestExit') return;
    if (_vpnState != 'idle') await _disconnectVpn();
    if (_vpnState == 'idle') {
      await _trayChannel.invokeMethod<void>('exitNow');
    } else {
      await _trayChannel.invokeMethod<void>('cancelExit');
    }
  }

  Future<void> _restore() async {
    final auth = _auth;
    if (auth == null) return;
    setState(() => _busy = true);
    try {
      if (await auth.restore()) await _registerDevice(auth);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Не удалось проверить сохранённую сессию');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _deviceLabel => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone / iPad',
    TargetPlatform.macOS => 'Mac',
    TargetPlatform.windows => 'Windows',
    _ => 'Устройство',
  };

  Future<void> _registerDevice(AuthClient auth) async {
    try {
      _deviceId = await auth.ensureDeviceRegistered(_deviceLabel);
      _message = null;
      await _syncConfiguration(auth);
    } catch (_) {
      _deviceId = null;
      _hasUsableConfiguration = false;
      _message = 'Устройство не зарегистрировано. Повторите попытку.';
    }
  }

  Future<void> _syncConfiguration(AuthClient auth) async {
    final vault = _vault;
    final deviceId = _deviceId;
    final accountId = auth.accountId;
    if (vault == null || deviceId == null || accountId == null) {
      _hasUsableConfiguration = false;
      _configurationMessage = 'Проверка обновлений ещё не настроена';
      return;
    }
    try {
      await auth.refreshAccountStatus();
    } catch (_) {
      // Keep the last known status while the account server is unavailable.
    }
    final access = auth.vpnAccessStatus;
    if (access != null && access != 'approved') {
      _hasUsableConfiguration = false;
      await vault.clear();
      if (_vpnState != 'idle' && _vpnControlsAvailable) {
        await _stopVpn();
        _vpnState = 'idle';
        _vpnTransport = null;
      }
      _configurationMessage = switch (access) {
        'pending' => 'Аккаунт создан. Ожидаем решения администратора',
        'revoking' => 'Доступ к VPN отзывается',
        'deleting' => 'Аккаунт удаляется',
        _ => 'Доступ к VPN не выдан',
      };
      return;
    }
    try {
      final bundle = await ConfigurationSync(
        auth,
        vault,
      ).refresh(deviceId: deviceId, now: DateTime.now());
      _hasUsableConfiguration = bundle != null;
      _configurationMessage = bundle == null
          ? 'Сервер ещё не выдал конфигурацию этому устройству'
          : 'Проверенное обновление ${bundle.version} сохранено';
    } on BundleException {
      _hasUsableConfiguration = false;
      _configurationMessage =
          'Не удалось проверить подпись или срок обновления';
    } catch (error) {
      if (error is AuthException &&
          (auth.vpnAccessStatus == 'deleting' ||
              error.message == 'Sign in required' ||
              error.message == 'Account unavailable')) {
        _hasUsableConfiguration = false;
        await vault.clear();
        _configurationMessage = auth.vpnAccessStatus == 'deleting'
            ? 'Аккаунт удалён'
            : 'Войдите в аккаунт снова';
        return;
      }
      try {
        final cached = await vault.load(
          accountId: accountId,
          deviceId: deviceId,
          now: DateTime.now(),
        );
        _hasUsableConfiguration = cached != null;
        _configurationMessage = cached == null
            ? 'Не удалось получить обновление'
            : 'Сохранено проверенное обновление ${cached.version}; сервер недоступен';
      } catch (_) {
        _hasUsableConfiguration = false;
        _configurationMessage = 'Не удалось получить обновление';
      }
    }
  }

  Future<void> _checkUpdates() async {
    final auth = _auth;
    if (auth == null || _deviceId == null) return;
    setState(() => _busy = true);
    try {
      await _syncConfiguration(auth);
    } catch (_) {
      _hasUsableConfiguration = false;
      _configurationMessage = 'Не удалось обновить состояние доступа';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshVpnState() async {
    try {
      final state = await _vpnStatus();
      if (mounted) setState(() => _vpnState = state);
    } catch (_) {
      if (mounted) setState(() => _vpnState = 'error');
    }
  }

  Future<void> _connectVpn() async {
    final auth = _auth;
    final vault = _vault;
    final accountId = auth?.accountId;
    final deviceId = _deviceId;
    if (auth == null ||
        vault == null ||
        accountId == null ||
        deviceId == null) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _latencyMs = null;
      _latencyMessage = null;
      _measuringLatency = false;
      _latencyRequestId++;
    });
    List<int>? seed;
    try {
      try {
        await auth.refreshAccountStatus();
      } catch (_) {}
      if (auth.vpnAccessStatus != null && auth.vpnAccessStatus != 'approved') {
        throw const AuthException('VPN access has not been approved');
      }
      final bundle = await vault.load(
        accountId: accountId,
        deviceId: deviceId,
        now: DateTime.now(),
      );
      if (bundle == null) throw const BundleException('No saved configuration');
      final nodes = bundle.payload['nodes'] as List;
      seed = await auth.readDeviceSeed();
      var connected = false;
      var declined = false;
      nodeLoop:
      for (final rawNode in nodes) {
        final nodeId = (rawNode as Map<String, dynamic>)['id'] as String;
        final access = await vault.openNodeAccess(
          accountId: accountId,
          deviceId: deviceId,
          nodeId: nodeId,
          deviceSeed: seed,
          now: DateTime.now(),
        );
        final candidates = <({String name, Future<bool?> Function() start})>[
          if (access.hysteria2 != null)
            (name: 'Hysteria2', start: () => _startHysteria(access.hysteria2!)),
          if (access.vlessReality != null)
            (name: 'VLESS', start: () => _startVless(access.vlessReality!)),
        ];
        for (final candidate in candidates) {
          final result = await _attemptVpn(candidate.start);
          if (result == null) {
            declined = true;
            break nodeLoop;
          }
          if (result) {
            _vpnTransport = candidate.name;
            connected = true;
            break nodeLoop;
          }
        }
      }
      if (!connected) {
        _message = declined
            ? 'Подключение отменено в системном запросе'
            : 'Ни один VPN-канал сейчас не отвечает';
      }
    } catch (_) {
      _message = 'Не удалось открыть конфигурацию или запустить VPN';
    } finally {
      if (seed != null) seed.fillRange(0, seed.length, 0);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _startHysteria(Hysteria2Profile profile) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _androidVpn.connectHysteria(profile) ? true : null;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _windowsVpn.connect(
        DesktopEngineProfile.windowsTun(
          profile.xrayConfigJson(localSocksPort: 10808),
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _macVpn.connect(
        DesktopEngineProfile.macOsTun(
          profile.xrayConfigJson(localSocksPort: 10808),
          tunName: 'utun10',
        ),
      );
    }
    return false;
  }

  Future<bool?> _startVless(VlessRealityProfile profile) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _androidVpn.connect(profile) ? true : null;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _windowsVpn.connect(
        DesktopEngineProfile.windowsTun(
          profile.configJson(localSocksPort: 10808),
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _macVpn.connect(
        DesktopEngineProfile.macOsTun(
          profile.configJson(localSocksPort: 10808),
          tunName: 'utun10',
        ),
      );
    }
    return false;
  }

  Future<String> _vpnStatus() => switch (defaultTargetPlatform) {
    TargetPlatform.android => _androidVpn.status(),
    TargetPlatform.windows => _windowsVpn.status(),
    TargetPlatform.macOS => _macVpn.status(),
    _ => Future<String>.value('idle'),
  };

  Future<void> _stopVpn() => switch (defaultTargetPlatform) {
    TargetPlatform.android => _androidVpn.stop(),
    TargetPlatform.windows => _windowsVpn.stop(),
    TargetPlatform.macOS => _macVpn.stop(),
    _ => Future<void>.value(),
  };

  Future<int> _measureVpn() => switch (defaultTargetPlatform) {
    TargetPlatform.android => _androidVpn.measureLatency(),
    TargetPlatform.windows => _windowsVpn.measureLatency(),
    TargetPlatform.macOS => _macVpn.measureLatency(),
    _ => Future<int>.error(StateError('VPN control is unavailable')),
  };

  /// Accept a connection only after it passes an HTTPS request via the TUN.
  Future<bool?> _attemptVpn(Future<bool?> Function() start) async {
    try {
      final started = await start();
      if (started == null) return null;
      if (!started) return false;
      for (var attempt = 0; attempt < 30; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        _vpnState = await _vpnStatus();
        if (_vpnState == 'connected') return true;
        if (_vpnState == 'error') break;
      }
    } catch (_) {
      // Try the next transport after the current service has been stopped.
    }
    await _stopVpn();
    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _vpnState = await _vpnStatus();
      if (_vpnState == 'idle') return false;
    }
    throw StateError('VPN did not stop');
  }

  Future<void> _disconnectVpn() async {
    setState(() {
      _busy = true;
      _latencyMs = null;
      _latencyMessage = null;
      _measuringLatency = false;
      _latencyRequestId++;
    });
    try {
      await _stopVpn();
      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        _vpnState = await _vpnStatus();
        if (_vpnState == 'idle') break;
      }
      _message = _vpnState == 'idle'
          ? null
          : 'Система ещё завершает VPN. Повторите отключение.';
      if (_vpnState == 'idle') _vpnTransport = null;
    } catch (_) {
      _message = 'Не удалось остановить VPN';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _measureVpnLatency() async {
    if (_measuringLatency || _busy || _vpnState != 'connected') return;
    final requestId = ++_latencyRequestId;
    setState(() {
      _measuringLatency = true;
      _latencyMs = null;
      _latencyMessage = null;
    });
    try {
      final milliseconds = await _measureVpn();
      final state = await _vpnStatus();
      if (!mounted || requestId != _latencyRequestId) return;
      setState(() {
        _vpnState = state;
        if (state == 'connected') {
          _latencyMs = milliseconds;
        } else {
          _latencyMessage = 'VPN отключился во время проверки';
        }
      });
    } catch (_) {
      if (mounted && requestId == _latencyRequestId) {
        setState(
          () => _latencyMessage =
              'Не удалось измерить задержку. Проверьте VPN и повторите.',
        );
      }
    } finally {
      if (mounted && requestId == _latencyRequestId) {
        setState(() => _measuringLatency = false);
      }
    }
  }

  Future<void> _retryDevice() async {
    final auth = _auth;
    if (auth == null || !auth.signedIn) return;
    setState(() => _busy = true);
    await _registerDevice(auth);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _login() async {
    final auth = _auth;
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.loginWithKeycloak();
      await _registerDevice(auth);
    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _message = switch (error.message) {
            'Sign in cancelled' => 'Вход отменён',
            _ => 'Не удалось войти. Проверьте соединение с сервером',
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Сервер аккаунтов недоступен');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final auth = _auth;
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
      _latencyMs = null;
      _latencyMessage = null;
      _measuringLatency = false;
      _latencyRequestId++;
    });
    try {
      if (_vpnControlsAvailable) {
        await _stopVpn();
        _vpnState = 'idle';
      }
      await auth.logout();
      await _vault?.clear();
      _deviceId = null;
      _hasUsableConfiguration = false;
      _configurationMessage = 'На этом устройстве пока не сохранены';
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Не удалось отозвать сессию. Повторите выход позже',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _accountCard() {
    final auth = _auth;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Аккаунт', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (auth == null)
              const Text('HTTPS-адрес сервера аккаунтов ещё не настроен.')
            else if (auth.signedIn) ...[
              Text('Выполнен вход: ${auth.username ?? 'пользователь'}'),
              if (auth.vpnAccessStatus != null) ...[
                const SizedBox(height: 8),
                Text(switch (auth.vpnAccessStatus) {
                  'approved' => 'Доступ к VPN разрешён',
                  'pending' => 'Заявка на VPN ожидает решения администратора',
                  'revoking' => 'Доступ к VPN отзывается',
                  'deleting' => 'Аккаунт удаляется',
                  _ => 'Доступ к VPN не выдан',
                }),
              ],
              const SizedBox(height: 8),
              Text(
                _deviceId == null
                    ? 'Устройство ожидает регистрации'
                    : 'Устройство зарегистрировано',
              ),
              const SizedBox(height: 12),
              if (_deviceId == null) ...[
                OutlinedButton(
                  onPressed: _busy ? null : _retryDevice,
                  child: const Text('Повторить регистрацию'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton(
                onPressed: _busy ? null : _logout,
                child: const Text('Выйти'),
              ),
            ] else ...[
              const Text('Для входа откроется защищённая страница Ноны.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: const Text('Войти через Нону'),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Нона')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Виртуальный Помощник Нона',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Клиент VPN для ваших устройств',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              _accountCard(),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _vpnState == 'connected'
                                ? Icons.shield
                                : Icons.pause_circle_outline,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(switch (_vpnState) {
                              'connected' =>
                                _vpnTransport == null
                                    ? 'VPN подключён'
                                    : 'VPN подключён · $_vpnTransport',
                              'connecting' => 'Подключение VPN',
                              'disconnecting' => 'Отключение VPN',
                              'error' => 'Ошибка подключения',
                              _ => 'VPN не подключён',
                            }, style: Theme.of(context).textTheme.titleLarge),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_vpnControlsAvailable &&
                          (_vpnState != 'idle' ||
                              (_deviceId != null && _vault != null))) ...[
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : _vpnState != 'idle'
                              ? _disconnectVpn
                              : canStartVpn(
                                  busy: _busy,
                                  vpnState: _vpnState,
                                  accessStatus: _auth?.vpnAccessStatus,
                                  hasConfiguration: _hasUsableConfiguration,
                                )
                              ? _connectVpn
                              : null,
                          child: Text(
                            vpnActionLabel(
                              vpnState: _vpnState,
                              accessStatus: _auth?.vpnAccessStatus,
                              hasConfiguration: _hasUsableConfiguration,
                            ),
                          ),
                        ),
                        if (_vpnState == 'connected') ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _busy || _measuringLatency
                                ? null
                                : _measureVpnLatency,
                            icon: _measuringLatency
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.speed_outlined),
                            label: Text(
                              _measuringLatency
                                  ? 'Проверяем задержку…'
                                  : 'Проверить пинг',
                            ),
                          ),
                          if (_latencyMs != null) ...[
                            const SizedBox(height: 8),
                            Text('Задержка через VPN: $_latencyMs мс'),
                          ],
                          if (_latencyMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(_latencyMessage!),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Время ответа HTTPS-сайта через VPN, не пинг сервера.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ] else
                        Text(
                          'Подключение появится после входа и получения конфигурации.',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Конфигурации'),
                  subtitle: Text(_configurationMessage),
                  trailing: _deviceId == null || _vault == null
                      ? null
                      : IconButton(
                          tooltip: 'Проверить обновления',
                          onPressed: _busy ? null : _checkUpdates,
                          icon: const Icon(Icons.refresh),
                        ),
                ),
              ),
              if (defaultTargetPlatform == TargetPlatform.android)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.apps_outlined),
                    title: const Text('Интернет без VPN'),
                    subtitle: const Text(
                      'Сайты и приложения через обычную сеть',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const InternetRoutingScreen(),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'При подключении система запросит разрешение на VPN и покажет '
                'его статус. Приложение не скрывает этот факт от системы.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
