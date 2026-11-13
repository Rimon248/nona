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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:path_provider/path_provider.dart';

import 'connection_selection.dart';
import 'instant_page_route.dart';
import 'internet_routing_screen.dart';
import 'internet_routing.dart';
import 'routing_summary.dart';
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
import 'nona_control_screen.dart';
import 'nona_control_theme.dart';

void main() => runApp(const NonaApp());

class NonaApp extends StatelessWidget {
  const NonaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Виртуальный Помощник Нона',
      debugShowCheckedModeBanner: false,
      theme: buildNonaControlTheme(),
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
  Webview? _authenticationWindow;
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
  String? _lastConnectionError;
  String? _vpnTransport;
  String? _vpnCountry;
  String? _lastConnectedNodeId;
  String? _selectedNodeId;
  PreferredTransport _selectedTransport = PreferredTransport.automatic;
  bool _manualConnectionEnabled = false;
  List<ConnectionNodeOption> _availableNodes = const [];
  RoutingSummary? _routingSummary;
  InternetRoutingState? _routingData;
  bool _routingLoadFailed = false;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  int _selectedTab = 0;
  int? _latencyMs;
  bool _measuringLatency = false;
  String? _latencyMessage;
  int _latencyRequestId = 0;
  Timer? _updateTimer;
  DateTime? _lastConfigurationCheck;
  String? _lastPresentedMessage;

  static const MethodChannel _trayChannel = MethodChannel('nona.tray');

  bool get _vpnControlsAvailable =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  String get _manualPreferenceKey =>
      defaultTargetPlatform == TargetPlatform.android
      ? 'manual_connection_enabled'
      : 'manual_connection_enabled_desktop_v2';

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
          redirectUri:
              defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.macOS
              ? Uri.parse('http://127.0.0.1:0')
              : Uri.parse('ru.basketref.nona://oauth2redirect'),
          options: OidcPlatformSpecificOptions(
            windows: OidcPlatformSpecificOptions_Native(
              launchUrl: _openAuthenticationWindow,
              flowTimeoutSeconds: 180,
            ),
            macos: OidcNativeOptionsApple(
              navigationMode: OidcAppleNavigationMode.loopbackSystemBrowser,
              launchUrl: _openAuthenticationWindow,
              flowTimeoutSeconds: 180,
            ),
          ),
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
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_vpnState == 'other-vpn' && !_busy) {
        unawaited(_refreshVpnState());
      }
      if (!mounted || _busy || _auth?.signedIn != true || _deviceId == null) {
        return;
      }
      final interval = _hasUsableConfiguration
          ? const Duration(minutes: 2)
          : const Duration(seconds: 15);
      final lastCheck = _lastConfigurationCheck;
      if (lastCheck == null ||
          DateTime.now().difference(lastCheck) >= interval) {
        unawaited(_checkUpdates());
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    unawaited(_closeAuthenticationWindow());
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _trayChannel.setMethodCallHandler(null);
    }
    _oidc?.dispose();
    _http?.close();
    super.dispose();
  }

  Future<bool> _openAuthenticationWindow(Uri uri) async {
    if (uri.scheme != 'https' || uri.host != Uri.parse(_oidcIssuer).host) {
      throw const FormatException('Unexpected authentication address');
    }
    await _closeAuthenticationWindow();
    final support = await getApplicationSupportDirectory();
    final browser = await WebviewWindow.create(
      configuration: CreateConfiguration(
        title: 'Войти через Нону',
        windowWidth: 880,
        windowHeight: 720,
        windows: WindowsWebviewOptions(
          userDataFolder:
              '${support.path}${Platform.pathSeparator}NonaWebView2',
        ),
      ),
    );
    _authenticationWindow = browser;
    browser.onClose.then((_) {
      if (identical(_authenticationWindow, browser)) {
        _authenticationWindow = null;
      }
    });
    await browser.launch(uri.toString());
    return true;
  }

  Future<void> _closeAuthenticationWindow() async {
    final browser = _authenticationWindow;
    _authenticationWindow = null;
    if (browser != null) {
      try {
        await browser.close();
      } catch (_) {}
    }
  }

  Future<void> _handleTrayCall(MethodCall call) async {
    if (call.method != 'requestExit') return;
    try {
      if (await _windowsVpn.status() == 'connected') {
        await _windowsVpn.stop();
      }
    } catch (_) {
      // The Xray runtime lives in this process; Windows closes it when the
      // application exits even if its normal stop request failed.
    } finally {
      await _trayChannel.invokeMethod<void>('exitNow');
    }
  }

  Future<void> _restore() async {
    final auth = _auth;
    if (auth == null) return;
    setState(() => _busy = true);
    try {
      await _restoreConnectionPreference();
      if (await auth.restore()) await _registerDevice(auth);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Не удалось проверить сохранённую сессию');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreConnectionPreference() async {
    try {
      final nodeId = await _preferences.getString('preferred_node_id');
      final transportName = await _preferences.getString('preferred_transport');
      final manualEnabled =
          await _preferences.getBool(_manualPreferenceKey) ??
          defaultTargetPlatform != TargetPlatform.android;
      final lastNodeId = await _preferences.getString('last_connected_node_id');
      if (!mounted) return;
      setState(() {
        _manualConnectionEnabled = manualEnabled;
        _selectedNodeId = manualEnabled ? nodeId : null;
        _selectedTransport = manualEnabled
            ? PreferredTransport.values.firstWhere(
                (value) => value.name == transportName,
                orElse: () => PreferredTransport.automatic,
              )
            : PreferredTransport.automatic;
        _lastConnectedNodeId = lastNodeId;
      });
    } catch (_) {
      // Settings remain automatic if the platform store is unavailable.
    }
  }

  Future<void> _selectNode(String? nodeId) async {
    setState(() {
      _selectedNodeId = nodeId;
      final node = _availableNodes.where((item) => item.id == nodeId);
      if (nodeId != null &&
          node.isNotEmpty &&
          !node.first.supports(_selectedTransport)) {
        _selectedTransport = PreferredTransport.automatic;
      }
    });
    if (nodeId == null) {
      await _preferences.remove('preferred_node_id');
    } else {
      await _preferences.setString('preferred_node_id', nodeId);
    }
    await _preferences.setString(
      'preferred_transport',
      _selectedTransport.name,
    );
  }

  Future<void> _selectTransport(PreferredTransport transport) async {
    setState(() => _selectedTransport = transport);
    await _preferences.setString('preferred_transport', transport.name);
  }

  Future<void> _setManualConnectionEnabled(bool enabled) async {
    setState(() {
      _manualConnectionEnabled = enabled;
      if (!enabled) {
        _selectedNodeId = null;
        _selectedTransport = PreferredTransport.automatic;
      }
    });
    await _preferences.setBool(_manualPreferenceKey, enabled);
    if (!enabled) {
      await _preferences.remove('preferred_node_id');
      await _preferences.setString(
        'preferred_transport',
        PreferredTransport.automatic.name,
      );
    }
  }

  Future<void> _loadRoutingSummary() async {
    try {
      final data = await InternetRoutingClient().load();
      if (mounted) {
        setState(() {
          _routingData = data;
          _routingSummary = RoutingSummary.fromState(data);
          _routingLoadFailed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _routingData = null;
          _routingSummary = null;
          _routingLoadFailed = true;
        });
      }
    }
  }

  void _selectTab(int tab) {
    if (tab < 0 || tab > 2) return;
    setState(() => _selectedTab = tab);
    if (tab != 1 || _routingData != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedTab != 1 || _routingData != null) return;
      unawaited(_loadRoutingSummary());
    });
  }

  Future<void> _refreshCurrentPage() async {
    if (_selectedTab == 1) {
      await _loadRoutingSummary();
    } else if (_selectedTab == 0) {
      _lastConnectionError = null;
      await _refreshVpnState();
      if (_auth?.signedIn == true) await _checkUpdates();
      if (_vpnState == 'connected' && !_measuringLatency) {
        await _measureVpnLatency();
      }
    } else if (_auth?.signedIn == true) {
      await _checkUpdates();
    }
  }

  void _setAvailableNodes(VerifiedBundle? bundle) {
    _availableNodes = bundle == null
        ? const []
        : ConnectionNodeOption.fromBundle(bundle);
    if (bundle != null &&
        _selectedNodeId != null &&
        !_availableNodes.any((item) => item.id == _selectedNodeId)) {
      _selectedNodeId = null;
      unawaited(_preferences.remove('preferred_node_id'));
    }
    if (_vpnState == 'connected' && _vpnCountry == null) {
      for (final node in _availableNodes) {
        if (node.id == _lastConnectedNodeId) _vpnCountry = node.country;
      }
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
    } on AuthException catch (error) {
      _deviceId = null;
      _hasUsableConfiguration = false;
      _message = switch (error.message) {
        'Sign in required' => 'Сеанс входа истёк. Войдите через Нону снова.',
        'Device limit reached' => 'Достигнут лимит устройств аккаунта. Освободите место и повторите привязку.',
        'Device key already registered' =>
          'Ключ устройства уже зарегистрирован. Повторите привязку.',
        'Could not load devices' || 'Could not register device' =>
          'Сервер аккаунтов не привязал устройство. Повторите попытку.',
        _ => 'Не удалось привязать устройство. Войдите через Нону снова.',
      };
    } catch (_) {
      _deviceId = null;
      _hasUsableConfiguration = false;
      _message = 'Не удалось привязать устройство. Войдите через Нону снова.';
    }
  }

  Future<void> _syncConfiguration(AuthClient auth) async {
    _lastConfigurationCheck = DateTime.now();
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
      _setAvailableNodes(null);
      await vault.clear();
      if (_vpnState != 'idle' && _vpnControlsAvailable) {
        await _stopVpn();
        _vpnState = 'idle';
        _vpnTransport = null;
        _vpnCountry = null;
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
      _setAvailableNodes(bundle);
      _configurationMessage = bundle == null
          ? 'Сервер ещё не выдал конфигурацию этому устройству'
          : 'Проверенное обновление ${bundle.version} сохранено';
    } on BundleException {
      _hasUsableConfiguration = false;
      _setAvailableNodes(null);
      _configurationMessage =
          'Не удалось проверить подпись или срок обновления';
    } catch (error) {
      if (error is AuthException &&
          (auth.vpnAccessStatus == 'deleting' ||
              error.message == 'Sign in required' ||
              error.message == 'Account unavailable')) {
        _hasUsableConfiguration = false;
        _setAvailableNodes(null);
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
        _setAvailableNodes(cached);
        _configurationMessage = cached == null
            ? 'Не удалось получить обновление'
            : 'Сохранено проверенное обновление ${cached.version}; сервер недоступен';
      } catch (_) {
        _hasUsableConfiguration = false;
        _setAvailableNodes(null);
        _configurationMessage = 'Не удалось получить обновление';
      }
    }
  }

  Future<void> _checkUpdates() async {
    final auth = _auth;
    if (auth == null || _deviceId == null || _busy) return;
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

  Future<void> _retryConnection() async {
    setState(() => _lastConnectionError = null);
    await _refreshVpnState();
    if (_vpnState == 'idle' &&
        canStartVpn(
          busy: _busy,
          vpnState: _vpnState,
          accessStatus: _auth?.vpnAccessStatus,
          hasConfiguration: _hasUsableConfiguration,
        )) {
      await _connectVpn();
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
      _vpnState = 'connecting';
      _message = null;
      _lastConnectionError = null;
      _latencyMs = null;
      _latencyMessage = null;
      _measuringLatency = false;
      _latencyRequestId++;
    });
    List<int>? seed;
    var measureOnConnect = false;
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
      final preference = ConnectionPreference(
        nodeId: _manualConnectionEnabled ? _selectedNodeId : null,
        transport: _manualConnectionEnabled
            ? _selectedTransport
            : PreferredTransport.automatic,
      );
      final allowedIds = preference
          .eligibleNodes(_availableNodes)
          .map((node) => node.id)
          .toSet();
      final nodes = (bundle.payload['nodes'] as List)
          .where((raw) => allowedIds.contains((raw as Map)['id']))
          .toList();
      if (nodes.isEmpty) {
        throw const BundleException('Selected node is unavailable');
      }
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
          if (access.hysteria2 != null &&
              preference.allowsTransport('hysteria2'))
            (name: 'Hysteria2', start: () => _startHysteria(access.hysteria2!)),
          if (access.vlessReality != null &&
              preference.allowsTransport('vless-reality'))
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
            _vpnCountry = countryForEndpoint(rawNode['endpoint'] as String);
            _lastConnectedNodeId = nodeId;
            unawaited(_preferences.setString('last_connected_node_id', nodeId));
            connected = true;
            break nodeLoop;
          }
        }
      }
      if (!connected) {
        _message = declined
            ? 'Подключение отменено в системном запросе'
            : 'Ни один VPN-канал сейчас не отвечает';
        if (!declined) _lastConnectionError = _message;
      } else {
        measureOnConnect = true;
      }
    } on PlatformException catch (error) {
      _message = error.code == 'mac-vpn-startup'
          ? (error.message ?? 'Не удалось запустить VPN на Mac')
          : 'Не удалось открыть конфигурацию или запустить VPN';
      _lastConnectionError = _message;
    } catch (_) {
      _message = 'Не удалось открыть конфигурацию или запустить VPN';
      _lastConnectionError = _message;
    } finally {
      if (seed != null) seed.fillRange(0, seed.length, 0);
      if (mounted) {
        if (_lastConnectionError != null && _vpnState != 'connected') {
          _vpnState = 'blocked';
        } else if (_vpnState == 'connecting') {
          _vpnState = 'idle';
        }
        setState(() => _busy = false);
        if (measureOnConnect && _vpnState == 'connected') {
          unawaited(_measureVpnLatency());
        }
      }
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
          routing: await _desktopRoutingState(),
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _macVpn.connect(
        DesktopEngineProfile.macOsTun(
          profile.xrayConfigJson(localSocksPort: 10808),
          tunName: 'utun10',
          routing: await _desktopRoutingState(),
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
          routing: await _desktopRoutingState(),
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _macVpn.connect(
        DesktopEngineProfile.macOsTun(
          profile.configJson(localSocksPort: 10808),
          tunName: 'utun10',
          routing: await _desktopRoutingState(),
        ),
      );
    }
    return false;
  }

  Future<InternetRoutingState?> _desktopRoutingState() async {
    try {
      return await InternetRoutingClient().load();
    } catch (_) {
      return null;
    }
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
    } on PlatformException catch (error) {
      if (error.code == 'mac-vpn-cancelled') return null;
      if (error.code == 'mac-vpn-startup') rethrow;
      await _stopVpn();
      return false;
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
      if (_vpnState == 'idle') {
        _vpnTransport = null;
        _vpnCountry = null;
      }
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
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              error is PlatformException && error.code == 'create_failed'
              ? 'Не удалось открыть окно входа. На Windows проверьте WebView2 Runtime.'
              : 'Не удалось завершить вход: ${error.runtimeType}',
        );
      }
    } finally {
      await _closeAuthenticationWindow();
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
      _vpnCountry = null;
      _setAvailableNodes(null);
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

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null) {
      _lastPresentedMessage = null;
    } else if (message != _lastPresentedMessage) {
      _lastPresentedMessage = message;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _message != message) return;
        final width = MediaQuery.sizeOf(context).width;
        final mobile = width < 1080;
        final horizontal = mobile ? 16.0 : (width - 720).clamp(32.0, width) / 2;
        final bottom = mobile
            ? MediaQuery.viewPaddingOf(context).bottom +
                  (_selectedTab == 0 ? 146 : 78)
            : 16.0;
        final messenger = ScaffoldMessenger.of(context);
        messenger.removeCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              message,
              softWrap: true,
              style: const TextStyle(color: NonaColor.cream, fontSize: 14),
            ),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottom),
            backgroundColor: NonaColor.raised,
            showCloseIcon: true,
            closeIconColor: NonaColor.cream,
            duration: const Duration(seconds: 12),
          ),
        );
      });
    }
    final signedIn = _auth?.signedIn == true;
    final canConnect = canStartVpn(
      busy: _busy,
      vpnState: _vpnState,
      accessStatus: _auth?.vpnAccessStatus,
      hasConfiguration: _hasUsableConfiguration,
    );
    final VoidCallback? mainAction;
    final VoidCallback? connectionAction;
    final String actionLabel;
    if (_vpnControlsAvailable &&
        _vpnState != 'idle' &&
        _vpnState != 'other-vpn' &&
        _vpnState != 'blocked') {
      connectionAction = _busy ? null : _disconnectVpn;
      mainAction = _vpnState == 'connected' && !_busy && !_measuringLatency
          ? _measureVpnLatency
          : null;
      actionLabel = _measuringLatency ? 'Проверяем пинг…' : 'Проверить пинг';
    } else if (!signedIn || _deviceId == null) {
      connectionAction = null;
      mainAction = _auth == null || _busy ? null : _login;
      actionLabel = 'Войти через Нону';
    } else if (!_vpnControlsAvailable) {
      connectionAction = null;
      mainAction = null;
      actionLabel = 'VPN пока недоступно';
    } else if (_vpnState == 'blocked') {
      connectionAction = null;
      mainAction = _busy ? null : () => unawaited(_retryConnection());
      actionLabel = 'Повторить попытку';
    } else {
      connectionAction = canConnect ? _connectVpn : null;
      mainAction = null;
      actionLabel = 'Проверить пинг';
    }
    final accessLabel = switch (_auth?.vpnAccessStatus) {
      'approved' => 'Доступ к VPN разрешён',
      'pending' => 'Ожидаем решения администратора',
      'revoking' => 'Доступ к VPN отзывается',
      'deleting' => 'Аккаунт удаляется',
      null => null,
      _ => 'Доступ к VPN не выдан',
    };
    final connectionBlockReason = _vpnState == 'other-vpn'
        ? 'Отключите другой VPN и дождитесь обновления состояния'
        : _vpnState == 'blocked'
        ? _lastConnectionError
        : _busy
        ? 'Подождите завершения действия'
        : !signedIn
        ? 'Войдите через Нону'
        : _deviceId == null
        ? 'Устройство ещё не зарегистрировано'
        : !_vpnControlsAvailable
        ? 'VPN пока недоступно'
        : _auth?.vpnAccessStatus != null && _auth?.vpnAccessStatus != 'approved'
        ? accessLabel
        : !_hasUsableConfiguration
        ? _configurationMessage
        : null;
    return NonaControlScreen(
      selectedTab: _selectedTab,
      onSelectTab: _selectTab,
      vpnState: _vpnState,
      signedIn: signedIn,
      accountConfigured: _auth != null,
      actionLabel: actionLabel,
      onAction: mainAction,
      onConnectionTap: connectionAction,
      onRefresh: _refreshCurrentPage,
      busy: _busy,
      measuringLatency: _measuringLatency,
      onMeasureLatency: _vpnState == 'connected' && !_busy && !_measuringLatency
          ? _measureVpnLatency
          : null,
      routingAvailable: _vpnControlsAvailable,
      onOpenRouting: _vpnControlsAvailable
          ? () async {
              await Navigator.of(context).push(
                instantPageRoute<void>(
                  InternetRoutingScreen(initialData: _routingData),
                ),
              );
              if (mounted) unawaited(_loadRoutingSummary());
            }
          : null,
      onOpenRouteCategory: _vpnControlsAvailable
          ? (category) async {
              await Navigator.of(context).push(
                instantPageRoute<void>(
                  InternetRoutingScreen(
                    initialCategory: category,
                    initialData: _routingData,
                  ),
                ),
              );
              if (mounted) unawaited(_loadRoutingSummary());
            }
          : null,
      onLogin: _auth == null ? null : _login,
      onLogout: _logout,
      onRetryDevice: _retryDevice,
      configurationMessage: _configurationMessage,
      connectionBlockReason: connectionBlockReason,
      country: _vpnCountry,
      transport: _vpnTransport,
      routingSummary: _routingSummary,
      routingLoadFailed: _routingLoadFailed,
      nodeOptions: _availableNodes,
      selectedNodeId: _selectedNodeId,
      selectedTransport: _selectedTransport,
      manualConnectionEnabled: _manualConnectionEnabled,
      onManualConnectionChanged: (enabled) =>
          unawaited(_setManualConnectionEnabled(enabled)),
      onSelectNode: (id) => unawaited(_selectNode(id)),
      onSelectTransport: (value) => unawaited(_selectTransport(value)),
      latencyMs: _latencyMs,
      latencyMessage: _latencyMessage,
      username: _auth?.username,
      accessLabel: accessLabel,
      deviceRegistered: _deviceId != null,
    );
  }
}
