import 'dart:io';

import 'package:flutter/material.dart';

import 'desktop_routing.dart';

typedef _SaveDesktopPolicy = Future<bool> Function(DesktopRoutingPolicy policy);

class DesktopRoutingScreen extends StatefulWidget {
  const DesktopRoutingScreen({super.key});

  @override
  State<DesktopRoutingScreen> createState() => _DesktopRoutingScreenState();
}

class _DesktopRoutingScreenState extends State<DesktopRoutingScreen> {
  DesktopRoutingPolicy? _policy;
  bool _saving = false;
  bool _zonesExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final policy = await DesktopRoutingStore.load();
      if (!mounted) return;
      setState(() {
        _policy = policy;
        _error = null;
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'Не удалось открыть настройки маршрутизации');
      }
    }
  }

  Future<bool> _save(DesktopRoutingPolicy next) async {
    if (_saving) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DesktopRoutingStore.save(next);
      if (mounted) setState(() => _policy = next);
      return true;
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Не удалось сохранить правило. Попробуйте ещё раз.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
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
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 4, 8, 12),
                      child: Text(
                        'Отмеченное идёт через обычную сеть. Остальной трафик идёт через VPN. '
                        'Изменения применятся после переподключения VPN.',
                      ),
                    ),
                    _sitesModeCard(policy),
                    const SizedBox(height: 8),
                    if (Platform.isWindows)
                      Card(
                        child: ListTile(
                          title: const Text('Приложения мимо VPN'),
                          subtitle: Text(
                            policy.directProcesses.isEmpty
                                ? 'Выберите программы, которые должны подключаться через обычную сеть'
                                : '${policy.directProcesses.length} программ идут напрямую',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(
                            _DesktopProcessesPage(policy: policy, save: _save),
                          ),
                        ),
                      )
                    else
                      const Card(
                        child: ListTile(
                          title: Text('Приложения мимо VPN'),
                          subtitle: Text(
                            'Маршрутизация отдельных программ на Mac сейчас недоступна. '
                            'Здесь можно настроить прямой маршрут для сайтов.',
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        title: const Text('Свои сайты напрямую'),
                        subtitle: Text(
                          policy.directSites.isEmpty
                              ? 'Добавьте сайты для прямого соединения'
                              : '${policy.directSites.length} сайтов идут напрямую',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(
                          _DesktopCustomSitesPage(policy: policy, save: _save),
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
                      padding: EdgeInsets.fromLTRB(8, 16, 8, 0),
                      child: Text(
                        'Правило сайта зависит от имени, доступного ядру в HTTP/TLS/QUIC. '
                        'Собственный защищённый DNS, скрытое имя сайта и подключение по IP '
                        'могут помешать распознаванию. В Windows выбранная программа использует '
                        'обычную сеть для всех своих соединений.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sitesModeCard(DesktopRoutingPolicy policy) {
    final enabled = policy.directZones.isNotEmpty;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Российские сайты напрямую'),
            subtitle: const Text(
              'Сайты в выбранных российских доменных зонах подключаются через обычную сеть.',
            ),
            value: enabled,
            onChanged: _saving
                ? null
                : (value) => _save(
                    policy.copyWith(
                      directZones: value
                          ? desktopRussianZones.keys.toSet()
                          : <String>{},
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => _zonesExpanded = !_zonesExpanded),
                  child: Text(_zonesExpanded ? 'Скрыть детали' : 'Подробнее'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      _open(_DesktopZonesPage(policy: policy, save: _save)),
                  child: const Text('Выбрать сайты'),
                ),
              ],
            ),
          ),
          if (_zonesExpanded)
            for (final zone in desktopRussianZones.entries)
              CheckboxListTile(
                title: Text('Все сайты в зоне ${zone.value}'),
                value: policy.directZones.contains(zone.key),
                onChanged: _saving
                    ? null
                    : (checked) => _save(
                        policy.copyWith(
                          directZones: checked == true
                              ? {...policy.directZones, zone.key}
                              : ({...policy.directZones}..remove(zone.key)),
                        ),
                      ),
              ),
        ],
      ),
    );
  }
}

class _DesktopZonesPage extends StatefulWidget {
  const _DesktopZonesPage({required this.policy, required this.save});
  final DesktopRoutingPolicy policy;
  final _SaveDesktopPolicy save;

  @override
  State<_DesktopZonesPage> createState() => _DesktopZonesPageState();
}

class _DesktopZonesPageState extends State<_DesktopZonesPage> {
  late DesktopRoutingPolicy _policy = widget.policy;

  Future<void> _set(String zone, bool enabled) async {
    final zones = {..._policy.directZones};
    if (enabled) {
      zones.add(zone);
    } else {
      zones.remove(zone);
    }
    final next = _policy.copyWith(directZones: zones);
    if (await widget.save(next) && mounted) setState(() => _policy = next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Российские сайты')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Отметка означает прямой маршрут. Доменные зоны включают все сайты в них; '
                'можно выбрать только нужные зоны.',
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final zone in desktopRussianZones.entries)
                    CheckboxListTile(
                      title: Text('Все сайты в зоне ${zone.value}'),
                      value: _policy.directZones.contains(zone.key),
                      onChanged: (value) => _set(zone.key, value == true),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DesktopCustomSitesPage extends StatefulWidget {
  const _DesktopCustomSitesPage({required this.policy, required this.save});
  final DesktopRoutingPolicy policy;
  final _SaveDesktopPolicy save;

  @override
  State<_DesktopCustomSitesPage> createState() =>
      _DesktopCustomSitesPageState();
}

class _DesktopCustomSitesPageState extends State<_DesktopCustomSitesPage> {
  late DesktopRoutingPolicy _policy = widget.policy;
  String _search = '';
  String? _error;

  Future<void> _add() async {
    final input = await _askSite(context, 'Добавить сайт');
    if (input == null) return;
    try {
      final domain = normalizeDesktopSite(input);
      final next = _policy.copyWith(
        directSites: {..._policy.directSites, domain},
        vpnSites: {..._policy.vpnSites}..remove(domain),
      );
      if (await widget.save(next) && mounted) {
        setState(() {
          _policy = next;
          _error = null;
        });
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _remove(String site) async {
    final next = _policy.copyWith(
      directSites: {..._policy.directSites}..remove(site),
    );
    if (await widget.save(next) && mounted) setState(() => _policy = next);
  }

  @override
  Widget build(BuildContext context) {
    final sites =
        _policy.directSites
            .where((site) => site.contains(_search.toLowerCase()))
            .toList()
          ..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Свои сайты напрямую')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Добавьте сайты, которые должны подключаться напрямую. Поддомены также пойдут через обычную сеть.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Найти сайт',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) =>
                      setState(() => _search = value.toLowerCase()),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: sites.isEmpty
                    ? const Center(child: Text('Сайты не добавлены'))
                    : ListView.builder(
                        itemCount: sites.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(sites[index]),
                          trailing: IconButton(
                            tooltip: 'Удалить ${sites[index]}',
                            onPressed: () => _remove(sites[index]),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _add,
              child: const Text('Добавить сайт'),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopProcessesPage extends StatefulWidget {
  const _DesktopProcessesPage({required this.policy, required this.save});
  final DesktopRoutingPolicy policy;
  final _SaveDesktopPolicy save;

  @override
  State<_DesktopProcessesPage> createState() => _DesktopProcessesPageState();
}

class _DesktopProcessesPageState extends State<_DesktopProcessesPage> {
  late DesktopRoutingPolicy _policy = widget.policy;
  List<String> _running = const [];
  String _search = '';
  bool _loading = true;
  bool _saving = false;
  bool _updatingAll = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final running = await WindowsProcessCatalog.running();
      if (mounted) setState(() => _running = running);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Не удалось прочитать список запущенных программ',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String name, bool direct) async {
    final processes = {..._policy.directProcesses};
    if (direct) {
      processes.add(name);
    } else {
      processes.remove(name);
    }
    final next = _policy.copyWith(directProcesses: processes);
    await _save(next);
  }

  Future<void> _selectAll() async {
    if (_saving || _updatingAll || _running.isEmpty) return;
    setState(() => _updatingAll = true);
    final next = _policy.copyWith(
      directProcesses: {..._policy.directProcesses, ..._running},
    );
    final saved = await _save(next);
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Отмечено приложений: ${_running.length}. Переподключите VPN, чтобы применить.',
          ),
        ),
      );
    }
    if (mounted) setState(() => _updatingAll = false);
  }

  Future<void> _clearAll() async {
    if (_saving || _updatingAll || _policy.directProcesses.isEmpty) return;
    setState(() => _updatingAll = true);
    final next = _policy.copyWith(directProcesses: <String>{});
    final saved = await _save(next);
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Выбор программ снят. Переподключите VPN, чтобы применить.',
          ),
        ),
      );
    }
    if (mounted) setState(() => _updatingAll = false);
  }

  Future<bool> _save(DesktopRoutingPolicy next) async {
    if (_saving) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.save(next);
      if (!mounted) return false;
      if (saved) {
        setState(() => _policy = next);
      } else {
        setState(() => _error = 'Не удалось сохранить выбор программ.');
      }
      return saved;
    } on Object {
      if (mounted) {
        setState(() => _error = 'Не удалось сохранить выбор программ.');
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add() async {
    final input = await _askValue(
      context,
      'Добавить программу',
      'например, chrome.exe',
    );
    if (input == null) return;
    try {
      final name = normalizeWindowsProcess(input);
      await _set(name, true);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {..._running, ..._policy.directProcesses}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final visible = names
        .where((name) => name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Приложения мимо VPN'),
        actions: [
          IconButton(
            tooltip: 'Обновить список',
            onPressed: _loading || _saving ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Добавить программу',
            onPressed: _saving ? null : _add,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Отмеченные программы полностью обходят VPN. В списке показаны '
                  'приложения с открытым окном; фоновые программы можно добавить по имени .exe. '
                  'Список читается только на этом компьютере.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        _loading || _saving || _updatingAll || _running.isEmpty
                        ? null
                        : _selectAll,
                    icon: const Icon(Icons.select_all),
                    label: const Text('Выбрать все'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        _loading ||
                            _saving ||
                            _updatingAll ||
                            _policy.directProcesses.isEmpty
                        ? null
                        : _clearAll,
                    icon: const Icon(Icons.deselect),
                    label: const Text('Снять все выделения'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Найти приложение',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : visible.isEmpty
                    ? const Center(
                        child: Text('Подходящие приложения не найдены'),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final name = visible[index];
                          return CheckboxListTile(
                            title: Text('$name.exe'),
                            value: _policy.directProcesses.contains(name),
                            onChanged: _saving || _updatingAll
                                ? null
                                : (value) => _set(name, value == true),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> _askSite(BuildContext context, String title) => _askValue(
  context,
  title,
  'example.ru или https://пример.рф',
  label: 'Домен или HTTPS-адрес',
);

Future<String?> _askValue(
  BuildContext context,
  String title,
  String hint, {
  String? label,
}) async {
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        autofocus: true,
        keyboardType: label == null ? TextInputType.text : TextInputType.url,
        decoration: InputDecoration(labelText: label, hintText: hint),
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
