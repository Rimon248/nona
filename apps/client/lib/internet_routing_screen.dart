import 'package:flutter/material.dart';

import 'android_app_routing.dart';
import 'internet_routing.dart';

class InternetRoutingScreen extends StatefulWidget {
  const InternetRoutingScreen({super.key});

  @override
  State<InternetRoutingScreen> createState() => _InternetRoutingScreenState();
}

class _InternetRoutingScreenState extends State<InternetRoutingScreen> {
  final _client = InternetRoutingClient();
  InternetRoutingState? _data;
  InternetPolicy? _policy;
  bool _saving = false;
  bool _sitesExpanded = false;
  bool _appsExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _client.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _policy = data.policy;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Не удалось открыть настройки маршрутизации');
      }
    }
  }

  Future<bool> _save(InternetPolicy next) async {
    if (_saving) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.save(next);
      if (!mounted) return false;
      setState(() => _policy = next);
      return true;
    } catch (_) {
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

  Widget _modeCard({
    required String title,
    required String description,
    required DirectMode mode,
    required bool expanded,
    required VoidCallback toggleDetails,
    required ValueChanged<DirectMode> changeMode,
    required String allLabel,
    required String essentialLabel,
    required VoidCallback openList,
    required String listLabel,
  }) {
    final enabled = mode != DirectMode.off;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: Text(title),
            subtitle: Text(description),
            value: enabled,
            onChanged: _saving
                ? null
                : (value) =>
                      changeMode(value ? DirectMode.all : DirectMode.off),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: toggleDetails,
                  child: Text(expanded ? 'Скрыть детали' : 'Подробнее'),
                ),
                const Spacer(),
                TextButton(onPressed: openList, child: Text(listLabel)),
              ],
            ),
          ),
          if (expanded) ...[
            CheckboxListTile(
              title: Text(allLabel),
              value: mode == DirectMode.all,
              onChanged: !enabled || _saving
                  ? null
                  : (checked) => changeMode(
                      checked == true ? DirectMode.all : DirectMode.essential,
                    ),
            ),
            CheckboxListTile(
              title: Text(essentialLabel),
              value: mode == DirectMode.essential,
              onChanged: !enabled || mode == DirectMode.all || _saving
                  ? null
                  : (checked) => changeMode(
                      checked == true ? DirectMode.essential : DirectMode.all,
                    ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final policy = _policy;
    return Scaffold(
      appBar: AppBar(title: const Text('Интернет без VPN')),
      body: data == null || policy == null
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: Text(
                    'Отмеченное идёт через обычную сеть. Остальной трафик идёт через VPN. '
                    'Изменения применятся после переподключения VPN.',
                  ),
                ),
                _modeCard(
                  title: 'Российские сайты напрямую',
                  description:
                      'Сайты из российских доменных зон и каталога, '
                      'включая банки и сервисы, откроются через обычную сеть.',
                  mode: policy.sitesMode,
                  expanded: _sitesExpanded,
                  toggleDetails: () =>
                      setState(() => _sitesExpanded = !_sitesExpanded),
                  changeMode: (mode) => _save(policy.withSitesMode(mode)),
                  allLabel: 'Все российские сайты, банки и сервисы',
                  essentialLabel: 'Только банки и сервисы',
                  listLabel: 'Выбрать сайты',
                  openList: () => _open(
                    _SiteListPage(data: data, policy: policy, save: _save),
                  ),
                ),
                const SizedBox(height: 8),
                _modeCard(
                  title: 'Российские приложения напрямую',
                  description:
                      'Найденные приложения из каталога и с префиксом ru., '
                      'включая банки и сервисы, обойдут VPN целиком.',
                  mode: policy.appsMode,
                  expanded: _appsExpanded,
                  toggleDetails: () =>
                      setState(() => _appsExpanded = !_appsExpanded),
                  changeMode: (mode) => _save(policy.withAppsMode(mode)),
                  allLabel: 'Все российские приложения, банки и сервисы',
                  essentialLabel: 'Только банки и сервисы',
                  listLabel: 'Выбрать приложения',
                  openList: () => _open(
                    _AppListPage(
                      data: data,
                      policy: policy,
                      save: _save,
                      russianOnly: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: const Text('Свои сайты'),
                    subtitle: Text(
                      policy.customSites.isEmpty
                          ? 'Добавьте сайты для прямого соединения'
                          : '${policy.customSites.length} сайтов идут напрямую',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _open(_CustomSitesPage(policy: policy, save: _save)),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: const Text('Приложения мимо VPN'),
                    subtitle: const Text(
                      'Установленные программы и их текущий маршрут',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(
                      _AppListPage(
                        data: data,
                        policy: policy,
                        save: _save,
                        russianOnly: false,
                      ),
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
                    'Каталог не определяет происхождение каждого сайта или приложения. '
                    'Зашифрованное имя сайта и собственный DNS приложения могут помешать правилу для сайта. '
                    'Для важных приложений выберите прямой маршрут целиком.',
                  ),
                ),
              ],
            ),
    );
  }
}

typedef _SavePolicy = Future<bool> Function(InternetPolicy policy);

class _SiteListPage extends StatefulWidget {
  const _SiteListPage({
    required this.data,
    required this.policy,
    required this.save,
  });
  final InternetRoutingState data;
  final InternetPolicy policy;
  final _SavePolicy save;
  @override
  State<_SiteListPage> createState() => _SiteListPageState();
}

class _SiteListPageState extends State<_SiteListPage> {
  late InternetPolicy _policy = widget.policy;
  String _search = '';

  Future<void> _set(RussianSite site, bool direct) async {
    final next = _policy.withSite(site, direct);
    if (await widget.save(next) && mounted) setState(() => _policy = next);
  }

  @override
  Widget build(BuildContext context) {
    final sites = widget.data.sites
        .where(
          (site) =>
              site.label.toLowerCase().contains(_search.toLowerCase()) ||
              site.domain.contains(_search.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Российские сайты')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Отметка означает прямой маршрут. Доменные зоны включают все адреса в них; отдельные сайты можно исключить.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Найти сайт',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: sites.length,
              itemBuilder: (context, index) {
                final site = sites[index];
                return CheckboxListTile(
                  title: Text(site.label),
                  subtitle: Text(
                    site.zone
                        ? 'Все сайты в зоне ${site.label.split(' ').first}'
                        : site.domain,
                  ),
                  value: _policy.directSite(site),
                  onChanged: (value) => _set(site, value == true),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppListPage extends StatefulWidget {
  const _AppListPage({
    required this.data,
    required this.policy,
    required this.save,
    required this.russianOnly,
  });
  final InternetRoutingState data;
  final InternetPolicy policy;
  final _SavePolicy save;
  final bool russianOnly;
  @override
  State<_AppListPage> createState() => _AppListPageState();
}

class _AppListPageState extends State<_AppListPage> {
  late InternetPolicy _policy = widget.policy;
  String _search = '';

  Future<void> _set(String id, bool direct) async {
    final next = _policy.withApp(id, direct, widget.data.appCatalogue);
    if (await widget.save(next) && mounted) setState(() => _policy = next);
  }

  @override
  Widget build(BuildContext context) {
    final known = <String, LaunchableApp>{
      for (final app in widget.data.apps) app.packageName: app,
    };
    if (!widget.russianOnly) {
      for (final id in _policy.appOverrides.keys) {
        known.putIfAbsent(
          id,
          () => LaunchableApp(packageName: id, label: '$id (не найдено)'),
        );
      }
    }
    final apps =
        known.values.where((app) {
          final id = app.packageName;
          if (widget.russianOnly &&
              !id.startsWith('ru.') &&
              !widget.data.appCatalogue.containsKey(id)) {
            return false;
          }
          final query = _search.toLowerCase();
          return app.label.toLowerCase().contains(query) ||
              id.toLowerCase().contains(query);
        }).toList()..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.russianOnly ? 'Российские приложения' : 'Приложения мимо VPN',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              widget.russianOnly
                  ? 'Показаны установленные приложения с префиксом ru. и известные пакеты из каталога, включая com. Это предположение, проверьте выбор.'
                  : 'Отмеченные приложения полностью обходят VPN, в том числе в фоне. Список установленных программ читается только на устройстве и не отправляется на сервер.',
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
          Expanded(
            child: apps.isEmpty
                ? const Center(child: Text('Подходящие приложения не найдены'))
                : ListView.builder(
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return CheckboxListTile(
                        title: Text(app.label),
                        subtitle: Text(app.packageName),
                        value: _policy.directApp(
                          app.packageName,
                          widget.data.appCatalogue,
                        ),
                        onChanged: (value) =>
                            _set(app.packageName, value == true),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustomSitesPage extends StatefulWidget {
  const _CustomSitesPage({required this.policy, required this.save});
  final InternetPolicy policy;
  final _SavePolicy save;
  @override
  State<_CustomSitesPage> createState() => _CustomSitesPageState();
}

class _CustomSitesPageState extends State<_CustomSitesPage> {
  final _client = InternetRoutingClient();
  late InternetPolicy _policy = widget.policy;
  String? _error;

  Future<void> _add() async {
    var typed = '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить сайт'),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.url,
          onChanged: (value) => typed = value,
          decoration: const InputDecoration(
            labelText: 'Домен или HTTPS-адрес',
            hintText: 'example.ru',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, typed),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      final domain = await _client.normalizeSite(value);
      final next = _policy.withCustomSites([..._policy.customSites, domain]);
      if (await widget.save(next) && mounted) {
        setState(() {
          _policy = next;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Укажите домен или HTTPS-адрес сайта');
      }
    }
  }

  Future<void> _remove(String domain) async {
    final next = _policy.withCustomSites(
      _policy.customSites.where((item) => item != domain),
    );
    if (await widget.save(next) && mounted) setState(() => _policy = next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Свои сайты')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Укажите основной домен. Он и его поддомены будут идти через обычную сеть после переподключения VPN.',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _policy.customSites.isEmpty
              ? const Center(child: Text('Своих сайтов пока нет'))
              : ListView(
                  children: [
                    for (final domain in _policy.customSites)
                      ListTile(
                        title: Text(domain),
                        trailing: IconButton(
                          tooltip: 'Убрать $domain',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(domain),
                        ),
                      ),
                  ],
                ),
        ),
        SafeArea(
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
      ],
    ),
  );
}
