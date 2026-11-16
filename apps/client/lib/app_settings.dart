import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ConnectionPickerMode { hidden, country, transport, both }

class NonaSettings {
  const NonaSettings({
    this.updateNotifications = true,
    this.vpnActions = true,
    this.pingAction = false,
    this.connectionPicker = ConnectionPickerMode.hidden,
  });

  final bool updateNotifications;
  final bool vpnActions;
  final bool pingAction;
  final ConnectionPickerMode connectionPicker;

  NonaSettings copyWith({
    bool? updateNotifications,
    bool? vpnActions,
    bool? pingAction,
    ConnectionPickerMode? connectionPicker,
  }) => NonaSettings(
    updateNotifications: updateNotifications ?? this.updateNotifications,
    vpnActions: vpnActions ?? this.vpnActions,
    pingAction: pingAction ?? this.pingAction,
    connectionPicker: connectionPicker ?? this.connectionPicker,
  );

  static Future<NonaSettings> load(SharedPreferencesAsync preferences) async {
    final name = await preferences.getString('connection_picker_mode');
    final oldManual = await preferences.getBool('manual_connection_enabled');
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
  }
}

class NonaSettingsScreen extends StatefulWidget {
  const NonaSettingsScreen({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final NonaSettings settings;
  final ValueChanged<NonaSettings> onChanged;

  @override
  State<NonaSettingsScreen> createState() => _NonaSettingsScreenState();
}

class _NonaSettingsScreenState extends State<NonaSettingsScreen> {
  late NonaSettings settings = widget.settings;

  void change(NonaSettings value) {
    setState(() => settings = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Настройки')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
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
        const SizedBox(height: 20),
        const Text(
          'Главная',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const ListTile(
          title: Text('Выбор подключения'),
          subtitle: Text('Какие параметры можно выбирать на главной'),
        ),
        for (final (mode, label) in [
          (ConnectionPickerMode.hidden, 'Автоматически'),
          (ConnectionPickerMode.country, 'Только страна сервера'),
          (ConnectionPickerMode.transport, 'Только способ подключения'),
          (ConnectionPickerMode.both, 'Страна и способ подключения'),
        ])
          RadioListTile<ConnectionPickerMode>(
            title: Text(label),
            value: mode,
            groupValue: settings.connectionPicker,
            onChanged: (value) {
              if (value != null)
                change(settings.copyWith(connectionPicker: value));
            },
          ),
        const SizedBox(height: 12),
        const Text(
          'Для уведомлений об обновлениях разрешите уведомления Ноны в Android. Состояние активного VPN отображается в системной области.',
          style: TextStyle(fontSize: 13),
        ),
      ],
    ),
  );
}
