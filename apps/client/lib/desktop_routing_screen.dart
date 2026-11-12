import 'dart:io';

import 'package:flutter/material.dart';

import 'desktop_routing.dart';

class DesktopRoutingScreen extends StatefulWidget {
  const DesktopRoutingScreen({super.key});

  @override
  State<DesktopRoutingScreen> createState() => _DesktopRoutingScreenState();
}

class _DesktopRoutingScreenState extends State<DesktopRoutingScreen> {
  DesktopRoutingPolicy? _policy;
  List<String> _running = const [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final policy = await DesktopRoutingStore.load();
      List<String> running = const [];
      if (Platform.isWindows) {
        try {
          running = await WindowsProcessCatalog.running();
        } on Object {
          // Manual entry remains available when the process list is blocked.
        }
      }
      if (!mounted) return;
      setState(() {
        _policy = policy;
        _running = running;
        _error = null;
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'Не удалось открыть настройки маршрутизации');
      }
    }
  }

  Future<void> _save(DesktopRoutingPolicy next) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DesktopRoutingStore.save(next);
      if (mounted) setState(() => _policy = next);
    } on Object {
      if (mounted) setState(() => _error = 'Не удалось сохранить правило');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askValue(String title, String hint) async {
    var value = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onChanged: (typed) => value = typed,
          onSubmitted: (typed) => Navigator.pop(context, typed),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSite({required bool direct}) async {
    final input = await _askValue(
      direct ? 'Сайт напрямую' : 'Сайт через VPN',
      'example.ru или https://пример.рф',
    );
    if (input == null || _policy == null) return;
    try {
      final domain = normalizeDesktopSite(input);
      final policy = _policy!;
      await _save(
        policy.copyWith(
          directSites:
              direct ? {...policy.directSites, domain} : {...policy.directSites}
                ..remove(domain),
          vpnSites: direct
              ? ({...policy.vpnSites}..remove(domain))
              : {...policy.vpnSites, domain},
        ),
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _addProcess() async {
    final input = await _askValue('Программа напрямую', 'например, chrome.exe');
    if (input == null || _policy == null) return;
    try {
      final name = normalizeWindowsProcess(input);
      await _save(
        _policy!.copyWith(directProcesses: {..._policy!.directProcesses, name}),
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Widget _siteCard(DesktopRoutingPolicy policy, {required bool direct}) {
    final sites = (direct ? policy.directSites : policy.vpnSites).toList()
      ..sort();
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(
              direct ? 'Свои сайты напрямую' : 'Исключения: сайты через VPN',
            ),
            subtitle: Text(
              direct
                  ? 'Основной домен и его поддомены используют обычную сеть'
                  : 'Имеют приоритет перед правилом для всей доменной зоны',
            ),
            trailing: IconButton(
              tooltip: 'Добавить сайт',
              onPressed: _saving ? null : () => _addSite(direct: direct),
              icon: const Icon(Icons.add),
            ),
          ),
          for (final site in sites)
            ListTile(
              title: Text(site),
              trailing: IconButton(
                tooltip: 'Убрать $site',
                onPressed: _saving
                    ? null
                    : () => _save(
                        policy.copyWith(
                          directSites: direct
                              ? ({...policy.directSites}..remove(site))
                              : null,
                          vpnSites: direct
                              ? null
                              : ({...policy.vpnSites}..remove(site)),
                        ),
                      ),
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      ),
    );
  }

  Widget _processCard(DesktopRoutingPolicy policy) {
    final names = {..._running, ...policy.directProcesses}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Программы напрямую'),
            subtitle: const Text(
              'Выберите запущенную программу или добавьте имя её .exe файла',
            ),
            trailing: IconButton(
              tooltip: 'Добавить программу',
              onPressed: _saving ? null : _addProcess,
              icon: const Icon(Icons.add),
            ),
          ),
          for (final name in names)
            CheckboxListTile(
              title: Text('$name.exe'),
              value: policy.directProcesses.contains(name),
              onChanged: _saving
                  ? null
                  : (checked) => _save(
                      policy.copyWith(
                        directProcesses: checked == true
                            ? {...policy.directProcesses, name}
                            : ({...policy.directProcesses}..remove(name)),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    return Scaffold(
      appBar: AppBar(title: const Text('Интернет без VPN')),
      body: policy == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: _load,
                      child: Text('$_error. Повторить'),
                    ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Изменения применятся после переподключения VPN.',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          const ListTile(
                            title: Text('Российские доменные зоны напрямую'),
                            subtitle: Text(
                              'Включите зоны, сайты которых должны идти через обычную сеть',
                            ),
                          ),
                          for (final zone in desktopRussianZones.entries)
                            SwitchListTile(
                              title: Text('Все сайты в зоне ${zone.value}'),
                              value: policy.directZones.contains(zone.key),
                              onChanged: _saving
                                  ? null
                                  : (enabled) => _save(
                                      policy.copyWith(
                                        directZones: enabled
                                            ? {...policy.directZones, zone.key}
                                            : ({...policy.directZones}
                                                ..remove(zone.key)),
                                      ),
                                    ),
                            ),
                        ],
                      ),
                    ),
                    _siteCard(policy, direct: true),
                    _siteCard(policy, direct: false),
                    if (Platform.isWindows) _processCard(policy),
                    if (Platform.isMacOS)
                      const Card(
                        child: ListTile(
                          title: Text('Маршрутизация программ на Mac'),
                          subtitle: Text(
                            'Текущее ядро Xray определяет процессы для правил только в Windows и Linux. На Mac доступны правила сайтов.',
                          ),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Правило сайта зависит от имени, доступного ядру в HTTP/TLS/QUIC. Собственный защищённый DNS и скрытое имя сайта могут помешать распознаванию. В Windows выбор программы действует для всех её соединений.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
