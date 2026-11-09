import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'android_app_routing_screen.dart';
import 'auth_client.dart';
import 'config_bundle.dart';
import 'configuration_sync.dart';
import 'configuration_vault.dart';

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
  static const _configKeyId = String.fromEnvironment('NONA_CONFIG_KEY_ID');
  static const _configVerifyKey = String.fromEnvironment(
    'NONA_CONFIG_VERIFY_KEY_B64',
  );
  final _username = TextEditingController();
  final _password = TextEditingController();
  http.Client? _http;
  AuthClient? _auth;
  ConfigurationVault? _vault;
  String? _deviceId;
  String? _message;
  String _configurationMessage = 'На этом устройстве пока не сохранены';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_apiBaseUrl.isEmpty) return;
    try {
      _http = http.Client();
      _auth = AuthClient(
        baseUri: Uri.parse(_apiBaseUrl),
        httpClient: _http!,
        secureStore: PlatformSecureStringStore(),
      );
    } catch (_) {
      _message = 'Некорректный HTTPS-адрес сервера аккаунтов';
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
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _http?.close();
    super.dispose();
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
      _message = 'Устройство не зарегистрировано. Повторите попытку.';
    }
  }

  Future<void> _syncConfiguration(AuthClient auth) async {
    final vault = _vault;
    final deviceId = _deviceId;
    final accountId = auth.accountId;
    if (vault == null || deviceId == null || accountId == null) {
      _configurationMessage = 'Проверка обновлений ещё не настроена';
      return;
    }
    try {
      final bundle = await ConfigurationSync(
        auth,
        vault,
      ).refresh(deviceId: deviceId, now: DateTime.now());
      _configurationMessage = bundle == null
          ? 'Сервер ещё не выдал конфигурацию этому устройству'
          : 'Проверенное обновление ${bundle.version} сохранено';
    } on BundleException {
      _configurationMessage =
          'Не удалось проверить подпись или срок обновления';
    } catch (_) {
      try {
        final cached = await vault.load(
          accountId: accountId,
          deviceId: deviceId,
          now: DateTime.now(),
        );
        _configurationMessage = cached == null
            ? 'Не удалось получить обновление'
            : 'Сохранено проверенное обновление ${cached.version}; сервер недоступен';
      } catch (_) {
        _configurationMessage = 'Не удалось получить обновление';
      }
    }
  }

  Future<void> _checkUpdates() async {
    final auth = _auth;
    if (auth == null || _deviceId == null) return;
    setState(() => _busy = true);
    await _syncConfiguration(auth);
    if (mounted) setState(() => _busy = false);
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
      await auth.login(_username.text.trim(), _password.text);
      _password.clear();
      await _registerDevice(auth);
    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _message = switch (error.message) {
            'Invalid credentials' => 'Неверный логин или пароль',
            'Too many attempts' => 'Слишком много попыток. Попробуйте позже',
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
    });
    try {
      await auth.logout();
      await _vault?.clear();
      _deviceId = null;
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
              TextField(
                controller: _username,
                enabled: !_busy,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Логин'),
              ),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Пароль'),
                onSubmitted: (_) {
                  if (!_busy) _login();
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: const Text('Войти'),
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
                            Icons.pause_circle_outline,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Соединение не настроено',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Вход и проверка обновлений доступны при настроенном '
                        'сервере. VPN-подключение появится после автоматической '
                        'выдачи данных доступа и проверки сетевого модуля.',
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
                    title: const Text('Приложения без VPN'),
                    subtitle: const Text(
                      'Выбрать приложения для прямого соединения',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AndroidAppRoutingScreen(),
                      ),
                    ),
                  ),
                ),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.route_outlined),
                  title: Text('Маршрутизация'),
                  subtitle: Text(
                    'Маршруты для сайтов появятся после синхронизации',
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
