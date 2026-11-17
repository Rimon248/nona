import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update.dart';
import 'app_settings.dart';
import 'connection_selection.dart';
import 'nona_page_route.dart';
import 'internet_routing_screen.dart';
import 'internet_routing.dart';
import 'routing_summary.dart';
import 'macos_vpn_control.dart';
import 'android_vpn_control.dart';
import 'ios_vpn_control.dart';
import 'auth_client.dart';
import 'config_bundle.dart';
import 'configuration_sync.dart';
import 'configuration_vault.dart';
import 'desktop_engine_profile.dart';
import 'engine_profiles.dart';
import 'macos_compact_secure_storage.dart';
import 'vpn_action_policy.dart';
import 'windows_vpn_control.dart';
import 'nona_control_screen.dart';
import 'nona_control_theme.dart';
import 'nona_motion.dart';
import 'nona_startup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  ui.Image? startupFigure;
  try {
    final bytes = await rootBundle.load('assets/brand/nona-full-body.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    startupFigure = (await codec.getNextFrame()).image;
    codec.dispose();
  } catch (_) {
    // The rest of the application is still usable if an image is damaged.
  }
  runApp(NonaApp(startupFigure: startupFigure));
}

class NonaApp extends StatelessWidget {
  const NonaApp({super.key, required this.startupFigure});

  final ui.Image? startupFigure;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Виртуальный Помощник Нона',
      debugShowCheckedModeBanner: false,
      theme: buildNonaControlTheme(),
      home: HomeScreen(startupFigure: startupFigure),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.startupFigure});

  final ui.Image? startupFigure;

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
  final IosVpnControl _iosVpn = IosVpnControl();
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
  NonaSettings _settings = const NonaSettings();
  List<ConnectionNodeOption> _availableNodes = const [];
  RoutingSummary? _routingSummary;
  InternetRoutingState? _routingData;
  bool _routingLoadFailed = false;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  int _selectedTab = 0;
  int _previousTab = 0;
  bool _cardSortEntrance = false;
  int? _latencyMs;
  int _lastLatencyAt = 0;
  bool _measuringLatency = false;
  String? _latencyMessage;
  int _latencyRequestId = 0;
  Timer? _updateTimer;
  DateTime? _lastConfigurationCheck;
  String? _lastPresentedMessage;
  bool _starting = true;
  String _startupStatus = 'Проверяем вход и настройки';
  String _macHelperState = 'checking';
  bool _installingMacHelper = false;
  bool _windowsExiting = false;
  String? _lastWindowsTrayState;

  static const MethodChannel _windowChannel = MethodChannel('nona.window');
  static const MethodChannel _androidUiChannel = MethodChannel(
    'nona.android_ui',
  );

  bool get _vpnControlsAvailable =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  String get _manualPreferenceKey =>
      defaultTargetPlatform == TargetPlatform.android
      ? 'manual_connection_enabled'
      : 'manual_connection_enabled_desktop_v2';

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      unawaited(_refreshMacHelperState());
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _windowChannel.setMethodCallHandler(_handleWindowCall);
      unawaited(_loadWindowsSettings());
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      _androidUiChannel.setMethodCallHandler(_handleAndroidAction);
      unawaited(_loadAndroidSettings());
    }
    if (_vpnControlsAvailable) _refreshVpnState();
    if (_apiBaseUrl.isEmpty) {
      unawaited(_beginStartup());
      return;
    }
    final FlutterSecureStorage oidcSecureStorage = Platform.isMacOS
        ? MacCompactSecureStorage()
        : OidcDefaultStore.createHardenedSecureStorage();
    final secureStringStore = PlatformSecureStringStore(
      Platform.isMacOS ? oidcSecureStorage : null,
    );
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
        store: OidcDefaultStore(secureStorageInstance: oidcSecureStorage),
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
        secureStore: secureStringStore,
        oidcSession: KeycloakSession(_oidc!),
      );
    } catch (_) {
      _message = 'Некорректный HTTPS-адрес входа';
      unawaited(_beginStartup());
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
          secureStringStore,
          BundleVerifier({_configKeyId: key}),
        );
      } catch (_) {
        _configurationMessage = 'Неверный ключ проверки обновлений';
      }
    }
    unawaited(_beginStartup());
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
      _windowChannel.setMethodCallHandler(null);
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      _androidUiChannel.setMethodCallHandler(null);
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

  Future<void> _handleWindowCall(MethodCall call) async {
    if (call.method == 'trayAction') {
      await _handleWindowsTrayAction(call.arguments as String? ?? '');
      return;
    }
    if (call.method != 'requestExit') return;
    if (_settings.windowsCloseAction == WindowsCloseAction.hide) {
      await _windowChannel.invokeMethod<void>('hideWindow');
      return;
    }
    await _exitWindows();
  }

  Future<void> _exitWindows() async {
    if (_windowsExiting) return;
    _windowsExiting = true;
    while (_busy && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    try {
      _vpnState = await _vpnStatus();
    } catch (_) {
      _vpnState = 'error';
    }
    if (_vpnState != 'idle') await _disconnectVpn();
    await _windowChannel.invokeMethod<void>(
      _vpnState == 'idle' ? 'exitNow' : 'cancelExit',
    );
    _windowsExiting = false;
  }

  Future<void> _handleWindowsTrayAction(String action) async {
    if (!mounted) return;
    if (action == 'show') {
      await _windowChannel.invokeMethod<void>('showWindow');
      return;
    }
    if (action == 'quit') {
      await _exitWindows();
      return;
    }
    if (_starting || _busy) return;
    if (action == 'connect' || action == 'restart') {
      await _handleQuickAction(action == 'connect' ? 'CONNECT' : 'RESTART');
      if (_vpnState != 'connected') {
        await _windowChannel.invokeMethod<void>('showWindow');
      }
      return;
    }
    if (action == 'disconnect') {
      if (_vpnState == 'connected') await _disconnectVpn();
      return;
    }
    if (action == 'ping') {
      await _measureVpnLatency();
      return;
    }
    if (action.startsWith('node:') &&
        _settings.connectionPicker != ConnectionPickerMode.hidden &&
        _settings.connectionPicker != ConnectionPickerMode.transport) {
      final id = action.substring(5);
      if (id.isNotEmpty && !_availableNodes.any((node) => node.id == id)) {
        return;
      }
      if ((id.isEmpty ? null : id) == _selectedNodeId) return;
      await _selectNode(id.isEmpty ? null : id);
      if (_vpnState == 'connected') await _handleQuickAction('RESTART');
      return;
    }
    if (action.startsWith('transport:') &&
        _settings.connectionPicker != ConnectionPickerMode.hidden &&
        _settings.connectionPicker != ConnectionPickerMode.country) {
      final name = action.substring(10);
      final selected = PreferredTransport.values.where(
        (value) => value.name == name,
      );
      if (selected.isEmpty || selected.first == _selectedTransport) return;
      final node = _availableNodes.where(
        (value) => value.id == _selectedNodeId,
      );
      if (node.isNotEmpty && !node.first.supports(selected.first)) return;
      await _selectTransport(selected.first);
      if (_vpnState == 'connected') await _handleQuickAction('RESTART');
    }
  }

  Future<void> _refreshMacHelperState() async {
    try {
      final status = await _macVpn.helperStatus();
      if (mounted) setState(() => _macHelperState = status);
    } catch (_) {
      if (mounted) setState(() => _macHelperState = 'error');
    }
  }

  Future<void> _installMacHelper() async {
    if (_installingMacHelper) return;
    setState(() => _installingMacHelper = true);
    try {
      final status = await _macVpn.installHelper();
      if (mounted) setState(() => _macHelperState = status);
    } catch (_) {
      if (mounted) setState(() => _macHelperState = 'error');
    } finally {
      if (mounted) setState(() => _installingMacHelper = false);
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

  Future<void> _beginStartup() async {
    final started = DateTime.now();
    if (_auth != null) await _restore();
    if (!mounted) return;
    setState(() => _startupStatus = 'Проверяем обновления');

    AppUpdate? update;
    if (defaultTargetPlatform != TargetPlatform.android || kReleaseMode) {
      final client = http.Client();
      try {
        final package = await PackageInfo.fromPlatform();
        update = await GitHubUpdateChecker(client).check(
          installedVersion: package.version,
          platform: defaultTargetPlatform,
        );
        if (update != null &&
            await _preferences.getString('dismissed_update_tag') ==
                update.tag) {
          update = null;
        }
      } catch (_) {
        // A GitHub outage must not prevent use of saved VPN configuration.
      } finally {
        client.close();
      }
    }
    final remaining =
        const Duration(milliseconds: 900) - DateTime.now().difference(started);
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    if (!mounted) return;
    if (update != null) {
      if (defaultTargetPlatform == TargetPlatform.android &&
          _settings.updateNotifications) {
        unawaited(
          _androidUiChannel.invokeMethod<void>('showUpdate', {
            'version': update.version,
            'tag': update.tag,
          }),
        );
      }
      await _offerAppUpdate(update);
    }
    if (mounted) {
      setState(() {
        _starting = false;
        _cardSortEntrance = true;
      });
      Future<void>.delayed(const Duration(milliseconds: 950), () {
        if (mounted) setState(() => _cardSortEntrance = false);
      });
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_consumeAndroidAction());
      if (_settings.updateNotifications) {
        unawaited(
          _androidUiChannel.invokeMethod<void>('requestNotificationPermission'),
        );
      }
    }
  }

  Future<void> _offerAppUpdate(AppUpdate update) async {
    final android = defaultTargetPlatform == TargetPlatform.android;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('Доступна Нона ${update.version}'),
        content: Text(
          android ? 'Скачать обновление и открыть системное окно установки?' : 'Для этой платформы опубликована новая версия. Откройте выпуск, чтобы установить её.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(android ? 'Обновить' : 'Открыть выпуск'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted != true) {
      await _preferences.setString('dismissed_update_tag', update.tag);
      return;
    }
    if (android) {
      setState(() => _startupStatus = 'Скачиваем обновление');
      try {
        await AndroidAppInstaller().install(update);
      } on PlatformException catch (error) {
        _message = switch (error.code) {
          'INSTALL_PERMISSION' => 'Разрешите Ноне установку обновлений в системных настройках и повторите попытку.',
          'BAD_APK' => 'Скачанное обновление не прошло проверку.',
          _ => 'Не удалось скачать или открыть обновление. Попробуйте позже.',
        };
      } catch (_) {
        _message =
            'Не удалось скачать или открыть обновление. Попробуйте позже.';
      }
    } else {
      try {
        if (Platform.isMacOS) {
          await Process.start('open', [update.downloadUrl.toString()]);
        } else if (Platform.isWindows) {
          await Process.start('cmd', [
            '/c',
            'start',
            '',
            update.downloadUrl.toString(),
          ]);
        }
      } catch (_) {
        _message = 'Не удалось открыть страницу обновления';
      }
    }
  }

  Future<void> _restoreConnectionPreference() async {
    try {
      final nodeId = await _preferences.getString('preferred_node_id');
      final transportName = await _preferences.getString('preferred_transport');
      final platformSettings =
          defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.windows
          ? await NonaSettings.load(_preferences)
          : null;
      final manualEnabled = platformSettings != null
          ? platformSettings.connectionPicker != ConnectionPickerMode.hidden
          : await _preferences.getBool(_manualPreferenceKey) ?? true;
      final lastNodeId = await _preferences.getString('last_connected_node_id');
      if (!mounted) return;
      setState(() {
        _manualConnectionEnabled = manualEnabled;
        if (platformSettings != null) _settings = platformSettings;
        _selectedNodeId =
            manualEnabled &&
                platformSettings?.connectionPicker !=
                    ConnectionPickerMode.transport
            ? nodeId
            : null;
        _selectedTransport =
            manualEnabled &&
                platformSettings?.connectionPicker !=
                    ConnectionPickerMode.country
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

  Future<void> _loadAndroidSettings() async {
    final settings = await NonaSettings.load(_preferences);
    if (!mounted) return;
    setState(() => _settings = settings);
    await _androidUiChannel.invokeMethod<void>('setSettings', {
      'updates': settings.updateNotifications,
      'vpnActions': settings.vpnActions,
      'pingAction': settings.pingAction,
    });
    if (settings.updateNotifications) {
      await _androidUiChannel.invokeMethod<void>(
        'requestNotificationPermission',
      );
    }
  }

  Future<void> _loadWindowsSettings() async {
    try {
      final settings = await NonaSettings.load(_preferences);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _manualConnectionEnabled =
            settings.connectionPicker != ConnectionPickerMode.hidden;
      });
    } catch (_) {
      // Keep the default settings if the platform store is unavailable.
    }
  }

  Future<void> _saveWindowsSettings(NonaSettings settings) async {
    final updateAutoStart =
        settings.windowsAutoStart != _settings.windowsAutoStart ||
        (settings.windowsAutoStart &&
            settings.windowsStartHidden != _settings.windowsStartHidden);
    setState(() {
      _settings = settings;
      _manualConnectionEnabled =
          settings.connectionPicker != ConnectionPickerMode.hidden;
      if (settings.connectionPicker == ConnectionPickerMode.hidden ||
          settings.connectionPicker == ConnectionPickerMode.transport) {
        _selectedNodeId = null;
      }
      if (settings.connectionPicker == ConnectionPickerMode.hidden ||
          settings.connectionPicker == ConnectionPickerMode.country) {
        _selectedTransport = PreferredTransport.automatic;
      }
    });
    await settings.save(_preferences);
    await _preferences.setBool(_manualPreferenceKey, _manualConnectionEnabled);
    if (_selectedNodeId == null) await _preferences.remove('preferred_node_id');
    await _preferences.setString(
      'preferred_transport',
      _selectedTransport.name,
    );
    if (updateAutoStart) {
      try {
        await _windowChannel.invokeMethod<void>('setAutoStart', {
          'enabled': settings.windowsAutoStart,
          'hidden': settings.windowsStartHidden,
        });
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось изменить запуск вместе с Windows'),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveAndroidSettings(NonaSettings settings) async {
    final requestPermission =
        !_settings.updateNotifications && settings.updateNotifications;
    setState(() {
      _settings = settings;
      _manualConnectionEnabled =
          settings.connectionPicker != ConnectionPickerMode.hidden;
      if (settings.connectionPicker == ConnectionPickerMode.hidden ||
          settings.connectionPicker == ConnectionPickerMode.transport) {
        _selectedNodeId = null;
      }
      if (settings.connectionPicker == ConnectionPickerMode.hidden ||
          settings.connectionPicker == ConnectionPickerMode.country) {
        _selectedTransport = PreferredTransport.automatic;
      }
    });
    await settings.save(_preferences);
    await _preferences.setBool(_manualPreferenceKey, _manualConnectionEnabled);
    if (_selectedNodeId == null) await _preferences.remove('preferred_node_id');
    await _preferences.setString(
      'preferred_transport',
      _selectedTransport.name,
    );
    await _androidUiChannel.invokeMethod<void>('setSettings', {
      'updates': settings.updateNotifications,
      'vpnActions': settings.vpnActions,
      'pingAction': settings.pingAction,
    });
    if (requestPermission) {
      await _androidUiChannel.invokeMethod<void>(
        'requestNotificationPermission',
        true,
      );
    }
  }

  Future<void> _consumeAndroidAction() async {
    final action = await _androidUiChannel.invokeMethod<String>(
      'pendingAction',
    );
    if (action != null) await _handleQuickAction(action);
  }

  Future<void> _handleAndroidAction(MethodCall call) async {
    if (call.method == 'quickAction' && call.arguments is String) {
      await _handleQuickAction(call.arguments as String);
    } else if (call.method == 'presentationChanged') {
      await _refreshVpnState();
    }
  }

  Future<void> _syncAndroidPresentation() async {
    try {
      final snapshot = await _androidUiChannel.invokeMapMethod<String, dynamic>(
        'presentationSnapshot',
      );
      if (!mounted || _vpnState != 'connected' || snapshot == null) return;
      final country = snapshot['country'] as String?;
      final latencyAt = snapshot['latencyAt'] as int? ?? 0;
      setState(() {
        if (country != null) _vpnCountry = country;
        if (latencyAt > 0 && latencyAt >= _lastLatencyAt) {
          _lastLatencyAt = latencyAt;
          _latencyMs = snapshot['latency'] as int?;
          _latencyMessage = snapshot['latencyMessage'] as String?;
        }
      });
    } catch (_) {
      // A presentation refresh does not affect VPN control.
    }
  }

  Future<void> _clearAndroidReconnect() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _androidUiChannel.invokeMethod<void>('clearReconnect');
    } catch (_) {}
  }

  Future<void> _handleQuickAction(String action) async {
    if (!mounted) return;
    if (_starting || _busy) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return _handleQuickAction(action);
    }
    await _refreshVpnState();
    if (action == 'PING') {
      if (_vpnState == 'connected') await _measureVpnLatency();
      return;
    }
    if (action == 'RESTART' && _vpnState == 'connected') {
      await _disconnectVpn();
      await _refreshVpnState();
    }
    if ((action == 'CONNECT' || action == 'RESTART') &&
        _vpnState == 'idle' &&
        canStartVpn(
          busy: _busy,
          vpnState: _vpnState,
          accessStatus: _auth?.vpnAccessStatus,
          hasConfiguration: _hasUsableConfiguration,
        )) {
      await _connectVpn();
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
    setState(() {
      _previousTab = _selectedTab;
      _selectedTab = tab;
    });
    if (tab != 1 || _routingData != null) return;
    Future<void>.delayed(NonaMotion.duration(context, NonaMotion.page), () {
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
      await _clearAndroidReconnect();
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
      if (bundle == null) await _clearAndroidReconnect();
      _configurationMessage = bundle == null
          ? 'Сервер ещё не выдал конфигурацию этому устройству'
          : 'Проверенное обновление ${bundle.version} сохранено';
    } on BundleException {
      _hasUsableConfiguration = false;
      _setAvailableNodes(null);
      await _clearAndroidReconnect();
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
        await _clearAndroidReconnect();
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
        await _clearAndroidReconnect();
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
      if (mounted) {
        setState(() {
          _vpnState = state;
          if (state != 'connected') {
            _latencyMs = null;
            _latencyMessage = null;
            _lastLatencyAt = 0;
          }
        });
      }
      if (defaultTargetPlatform == TargetPlatform.android &&
          state == 'connected') {
        await _syncAndroidPresentation();
      }
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
    final timing = Stopwatch()..start();
    void mark(String stage) {
      if (kDebugMode) {
        debugPrint('Nona connect: $stage at ${timing.elapsedMilliseconds} ms');
      }
    }

    void onFrames(List<ui.FrameTiming> frames) {
      if (!kDebugMode) return;
      for (final frame in frames) {
        if (frame.totalSpan.inMilliseconds < 34) continue;
        debugPrint(
          'Nona connect frame: total ${frame.totalSpan.inMilliseconds} ms, '
          'build ${frame.buildDuration.inMilliseconds} ms, '
          'raster ${frame.rasterDuration.inMilliseconds} ms',
        );
      }
    }

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
      _lastLatencyAt = 0;
      _latencyMessage = null;
      _measuringLatency = false;
      _latencyRequestId++;
    });
    if (kDebugMode) WidgetsBinding.instance.addTimingsCallback(onFrames);
    mark('pressed');
    List<int>? seed;
    var measureOnConnect = false;
    try {
      await Future.any<void>([
        WidgetsBinding.instance.endOfFrame,
        Future<void>.delayed(const Duration(milliseconds: 80)),
      ]);
      mark('first frame');
      try {
        await auth.refreshAccountStatus();
      } catch (_) {}
      mark('account status');
      if (auth.vpnAccessStatus != null && auth.vpnAccessStatus != 'approved') {
        throw const AuthException('VPN access has not been approved');
      }
      final bundle = await vault.load(
        accountId: accountId,
        deviceId: deviceId,
        now: DateTime.now(),
      );
      mark('configuration opened');
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
      mark('device key opened');
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
        mark('node access opened');
        final candidates = <({String name, Future<bool?> Function() start})>[
          if (access.hysteria2 != null &&
              preference.allowsTransport('hysteria2'))
            (name: 'Hysteria2', start: () => _startHysteria(access.hysteria2!)),
          if (access.vlessReality != null &&
              preference.allowsTransport('vless-reality'))
            (name: 'VLESS', start: () => _startVless(access.vlessReality!)),
        ];
        for (final candidate in candidates) {
          mark('starting transport');
          final result = await _attemptVpn(candidate.start);
          mark('transport returned');
          if (result == null) {
            declined = true;
            break nodeLoop;
          }
          if (result) {
            _vpnTransport = candidate.name;
            _vpnCountry = countryForEndpoint(rawNode['endpoint'] as String);
            if (defaultTargetPlatform == TargetPlatform.android) {
              unawaited(
                _androidUiChannel.invokeMethod<void>('presentation', {
                  'country': _vpnCountry,
                }),
              );
            }
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
      if (kDebugMode) WidgetsBinding.instance.removeTimingsCallback(onFrames);
      mark('finished');
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
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _iosVpn.connectHysteria(profile);
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
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _iosVpn.connect(profile);
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
    TargetPlatform.iOS => _iosVpn.status(),
    TargetPlatform.windows => _windowsVpn.status(),
    TargetPlatform.macOS => _macVpn.status(),
    _ => Future<String>.value('idle'),
  };

  Future<void> _stopVpn() => switch (defaultTargetPlatform) {
    TargetPlatform.android => _androidVpn.stop(),
    TargetPlatform.iOS => _iosVpn.stop(),
    TargetPlatform.windows => _windowsVpn.stop(),
    TargetPlatform.macOS => _macVpn.stop(),
    _ => Future<void>.value(),
  };

  Future<int> _measureVpn() => switch (defaultTargetPlatform) {
    TargetPlatform.android => _androidVpn.measureLatency(),
    TargetPlatform.iOS => _iosVpn.measureLatency(),
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
      _lastLatencyAt = 0;
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
          _lastLatencyAt = DateTime.now().millisecondsSinceEpoch;
        } else {
          _latencyMessage = 'VPN отключился во время проверки';
        }
      });
      if (defaultTargetPlatform == TargetPlatform.android &&
          state == 'connected') {
        unawaited(
          _androidUiChannel.invokeMethod<void>('latency', milliseconds),
        );
      }
    } catch (_) {
      if (mounted && requestId == _latencyRequestId) {
        setState(() {
          _latencyMessage =
              'Не удалось измерить задержку. Проверьте VPN и повторите.';
          _lastLatencyAt = DateTime.now().millisecondsSinceEpoch;
        });
        if (defaultTargetPlatform == TargetPlatform.android &&
            _vpnState == 'connected') {
          unawaited(_androidUiChannel.invokeMethod<void>('latencyError'));
        }
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
      await _clearAndroidReconnect();
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

  void _scheduleWindowsTrayUpdate() {
    final node = _availableNodes.where((item) => item.id == _selectedNodeId);
    final transports = node.isEmpty
        ? _availableNodes.expand((item) => item.transports).toSet()
        : node.first.transports;
    final state = <String, Object?>{
      'vpnState': _vpnState,
      'busy': _busy || _starting,
      'canConnect':
          !_starting &&
          canStartVpn(
            busy: _busy,
            vpnState: _vpnState,
            accessStatus: _auth?.vpnAccessStatus,
            hasConfiguration: _hasUsableConfiguration,
          ),
      'country': _vpnCountry ?? '',
      'latency': _latencyMs,
      'picker': _settings.connectionPicker.name,
      'selectedNode': _selectedNodeId ?? '',
      'selectedTransport': _selectedTransport.name,
      'nodes': [
        for (final item in _availableNodes)
          {'id': item.id, 'country': item.country},
      ],
      'transports': [
        if (transports.contains('hysteria2')) 'hysteria2',
        if (transports.contains('vless-reality')) 'vlessReality',
      ],
    };
    final encoded = jsonEncode(state);
    if (encoded == _lastWindowsTrayState) return;
    _lastWindowsTrayState = encoded;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _windowChannel.invokeMethod<void>('updateTray', state);
      } catch (_) {
        _lastWindowsTrayState = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _scheduleWindowsTrayUpdate();
    }
    return AnimatedSwitcher(
      duration: NonaMotion.duration(context, NonaMotion.startup),
      reverseDuration: NonaMotion.duration(
        context,
        const Duration(milliseconds: 380),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [?currentChild, ...previousChildren],
      ),
      transitionBuilder: (child, animation) =>
          child.key == const ValueKey('main-stage')
          ? child
          : FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey(_starting ? 'startup-stage' : 'main-stage'),
        child: RepaintBoundary(child: _buildContent(context)),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_starting) {
      return NonaStartupScreen(
        status: _startupStatus,
        figure: widget.startupFigure,
      );
    }
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
      previousTab: _previousTab,
      cardSortEntrance: _cardSortEntrance,
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
                nonaPageRoute<void>(
                  context,
                  InternetRoutingScreen(initialData: _routingData),
                ),
              );
              if (mounted) unawaited(_loadRoutingSummary());
            }
          : null,
      onOpenRouteCategory: _vpnControlsAvailable
          ? (category) async {
              await Navigator.of(context).push(
                nonaPageRoute<void>(
                  context,
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
      connectionPicker:
          defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.windows
          ? _settings.connectionPicker
          : ConnectionPickerMode.both,
      onOpenSettings:
          defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.windows
          ? () => Navigator.of(context).push(
              nonaPageRoute<void>(
                context,
                NonaSettingsScreen(
                  settings: _settings,
                  onChanged: (value) => unawaited(
                    defaultTargetPlatform == TargetPlatform.windows
                        ? _saveWindowsSettings(value)
                        : _saveAndroidSettings(value),
                  ),
                ),
              ),
            )
          : null,
      onManualConnectionChanged: (enabled) =>
          unawaited(_setManualConnectionEnabled(enabled)),
      onSelectNode: (id) => unawaited(_selectNode(id)),
      onSelectTransport: (value) => unawaited(_selectTransport(value)),
      latencyMs: _latencyMs,
      latencyMessage: _latencyMessage,
      username: _auth?.username,
      accessLabel: accessLabel,
      deviceRegistered: _deviceId != null,
      macHelperState: defaultTargetPlatform == TargetPlatform.macOS
          ? _macHelperState
          : null,
      onMacHelperAction: _installingMacHelper
          ? null
          : _macHelperState == 'notRegistered' ||
                _macHelperState == 'requiresApproval'
          ? _installMacHelper
          : _refreshMacHelperState,
    );
  }
}
