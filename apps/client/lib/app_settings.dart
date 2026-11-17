import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ConnectionPickerMode { hidden, country, transport, both }

enum WindowsCloseAction { exit, hide }

class NonaSettings {
  const NonaSettings({
    this.updateNotifications = true,
    this.vpnActions = true,
    this.pingAction = false,
    this.connectionPicker = ConnectionPickerMode.hidden,
    this.windowsAutoStart = false,
    this.windowsStartHidden = false,
    this.windowsCloseAction = WindowsCloseAction.exit,
  });

  final bool updateNotifications;
  final bool vpnActions;
  final bool pingAction;
  final ConnectionPickerMode connectionPicker;
  final bool windowsAutoStart;
  final bool windowsStartHidden;
  final WindowsCloseAction windowsCloseAction;

  NonaSettings copyWith({
    bool? updateNotifications,
    bool? vpnActions,
    bool? pingAction,
    ConnectionPickerMode? connectionPicker,
    bool? windowsAutoStart,
    bool? windowsStartHidden,
    WindowsCloseAction? windowsCloseAction,
  }) => NonaSettings(
    updateNotifications: updateNotifications ?? this.updateNotifications,
    vpnActions: vpnActions ?? this.vpnActions,
    pingAction: pingAction ?? this.pingAction,
    connectionPicker: connectionPicker ?? this.connectionPicker,
    windowsAutoStart: windowsAutoStart ?? this.windowsAutoStart,
    windowsStartHidden: windowsStartHidden ?? this.windowsStartHidden,
    windowsCloseAction: windowsCloseAction ?? this.windowsCloseAction,
  );

  static Future<NonaSettings> load(SharedPreferencesAsync preferences) async {
    final name = await preferences.getString('connection_picker_mode');
    final oldManual =
        await preferences.getBool('manual_connection_enabled') ??
        await preferences.getBool('manual_connection_enabled_desktop_v2');
    final closeActionName = await preferences.getString('windows_close_action');
    return NonaSettings(
      updateNotifications:
          await preferences.getBool('notify_app_updates') ?? true,
      vpnActions: await preferences.getBool('notify_vpn_actions') ?? true,
      pingAction: await preferences.getBool('notify_ping_action') ?? false,
      connectionPicker: ConnectionPickerMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => oldManual == true
            ? ConnectionPickerMode.both
            : ConnectionPickerMode.hidden,
      ),
      windowsAutoStart:
          await preferences.getBool('windows_auto_start') ?? false,
      windowsStartHidden:
          await preferences.getBool('windows_start_hidden') ?? false,
      windowsCloseAction: WindowsCloseAction.values.firstWhere(
        (action) => action.name == closeActionName,
        orElse: () => WindowsCloseAction.exit,
      ),
    );
  }

  Future<void> save(SharedPreferencesAsync preferences) async {
    await preferences.setBool('notify_app_updates', updateNotifications);
    await preferences.setBool('notify_vpn_actions', vpnActions);
    await preferences.setBool('notify_ping_action', pingAction);
    await preferences.setString(
      'connection_picker_mode',
      connectionPicker.name,
    );
    await preferences.setBool('windows_auto_start', windowsAutoStart);
    await preferences.setBool('windows_start_hidden', windowsStartHidden);
    await preferences.setString(
      'windows_close_action',
      windowsCloseAction.name,
    );
  }
}

class NonaSettingsScreen extends StatefulWidget {
  const NonaSettingsScreen({
    super.key,
    required this.settings,
    required this.onChanged,
    this.embedded = false,
  });

  final NonaSettings settings;
  final ValueChanged<NonaSettings> onChanged;
  final bool embedded;

  @override
  State<NonaSettingsScreen> createState() => _NonaSettingsScreenState();
}

class _NonaSettingsScreenState extends State<NonaSettingsScreen> {
  late NonaSettings settings = widget.settings;

  @override
  void didUpdateWidget(covariant NonaSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) settings = widget.settings;
  }

  void change(NonaSettings value) {
    setState(() => settings = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(20),
      children: [
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          const Text(
            'Уведомления',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          SwitchListTile.adaptive(
            title: const Text('Новая версия Ноны'),
            subtitle: const Text('Сообщать о доступном обновлении'),
            value: settings.updateNotifications,
            onChanged: (value) =>
                change(settings.copyWith(updateNotifications: value)),
          ),
          SwitchListTile.adaptive(
            title: const Text('Кнопки VPN в уведомлении'),
            subtitle: const Text('Перезапуск и отключение'),
            value: settings.vpnActions,
            onChanged: (value) => change(settings.copyWith(vpnActions: value)),
          ),
          SwitchListTile.adaptive(
            title: const Text('Проверка пинга в уведомлении'),
            subtitle: const Text('Показывать кнопку и последний результат'),
            value: settings.pingAction,
            onChanged: (value) => change(settings.copyWith(pingAction: value)),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Главная',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const ListTile(
          title: Text('Выбор подключения'),
          subtitle: Text('Какие параметры можно выбирать на главной'),
        ),
        RadioGroup<ConnectionPickerMode>(
          groupValue: settings.connectionPicker,
          onChanged: (value) =>
              change(settings.copyWith(connectionPicker: value)),
          child: Column(
            children: [
              for (final (mode, label) in [
                (ConnectionPickerMode.hidden, 'Автоматически'),
                (ConnectionPickerMode.country, 'Только страна сервера'),
                (ConnectionPickerMode.transport, 'Только способ подключения'),
                (ConnectionPickerMode.both, 'Страна и способ подключения'),
              ])
                RadioListTile<ConnectionPickerMode>(
                  title: Text(label),
                  value: mode,
                ),
            ],
          ),
        ),
        if (defaultTargetPlatform == TargetPlatform.windows) ...[
          const SizedBox(height: 20),
          const Text(
            'Windows',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          SwitchListTile.adaptive(
            title: const Text('Запускать вместе с Windows'),
            value: settings.windowsAutoStart,
            onChanged: (value) =>
                change(settings.copyWith(windowsAutoStart: value)),
          ),
          SwitchListTile.adaptive(
            title: const Text('Скрывать окно при запуске Windows'),
            subtitle: const Text(
              'Нона останется доступной через значок в трее',
            ),
            value: settings.windowsStartHidden,
            onChanged: settings.windowsAutoStart
                ? (value) =>
                      change(settings.copyWith(windowsStartHidden: value))
                : null,
          ),
          const SizedBox(height: 14),
          const Text(
            'При нажатии на крестик окна',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          RadioGroup<WindowsCloseAction>(
            groupValue: settings.windowsCloseAction,
            onChanged: (value) =>
                change(settings.copyWith(windowsCloseAction: value)),
            child: const Column(
              children: [
                RadioListTile<WindowsCloseAction>(
                  title: Text('Выключить Нону и VPN'),
                  value: WindowsCloseAction.exit,
                ),
                RadioListTile<WindowsCloseAction>(
                  title: Text('Скрыть окно, оставить VPN включённым'),
                  subtitle: Text('Нона продолжит работать в трее'),
                  value: WindowsCloseAction.hide,
                ),
              ],
            ),
          ),
        ],
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          const SizedBox(height: 12),
          const Text(
            'Для уведомлений об обновлениях разрешите уведомления Ноны в Android. Состояние активного VPN отображается в системной области.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ],
    );
    return widget.embedded
        ? content
        : Scaffold(
            appBar: AppBar(title: const Text('Настройки')),
            body: content,
          );
  }
}
