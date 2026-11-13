import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'android_app_routing.dart';
import 'delayed_progress_indicator.dart';
import 'instant_page_route.dart';
import 'internet_routing.dart';
import 'nona_control_theme.dart';

class InternetRoutingScreen extends StatefulWidget {
  const InternetRoutingScreen({
    super.key,
    this.initialCategory,
    this.initialData,
  });

  final String? initialCategory;
  final InternetRoutingState? initialData;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final data = widget.initialData;
      if (data == null) {
        unawaited(_load());
      } else {
        setState(() {
          _data = data;
          _policy = data.policy;
        });
      }
    });
  }

  Future<void> _load() async {
    if (mounted) {
      if (_error != null) setState(() => _error = null);
    }
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

  Future<void> _openCategory(String category) async {
    await Navigator.of(context).push(
      instantPageRoute<void>(
        InternetRoutingScreen(initialCategory: category, initialData: _data),
      ),
    );
    if (mounted) unawaited(_load());
  }

  Widget _modeCard({
    required String title,
    required String description,
    required DirectMode? mode,
    required bool expanded,
    required VoidCallback toggleDetails,
    required ValueChanged<DirectMode>? changeMode,
    required String allLabel,
    required String essentialLabel,
    required VoidCallback openList,
    required String listLabel,
  }) {
    final enabled = mode != null && mode != DirectMode.off;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: Text(title),
            subtitle: Text(description),
            value: enabled,
            onChanged: _saving || mode == null || changeMode == null
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
              onChanged: !enabled || _saving || changeMode == null
                  ? null
                  : (checked) => changeMode(
                      checked == true ? DirectMode.all : DirectMode.essential,
                    ),
            ),
            CheckboxListTile(
              title: Text(essentialLabel),
              value: mode == DirectMode.essential,
              onChanged:
                  !enabled ||
                      mode == DirectMode.all ||
                      _saving ||
                      changeMode == null
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
    final category = widget.initialCategory;
    if (category != null) {
      return switch (category) {
        'sites' => _SiteListPage(
          data: data,
          policy: policy,
          error: _error,
          retry: _load,
          save: _save,
        ),
        'russianApps' => _AppListPage(
          data: data,
          policy: policy,
          error: _error,
          retry: _load,
          save: _save,
          russianOnly: true,
        ),
        'apps' => _AppListPage(
          data: data,
          policy: policy,
          error: _error,
          retry: _load,
          save: _save,
          russianOnly: false,
        ),
        'customSites' => _CustomSitesPage(
          policy: policy,
          error: _error,
          retry: _load,
          save: _save,
        ),
        _ => const Scaffold(body: Center(child: Text('Раздел не найден'))),
      };
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Маршруты')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                const Text(
                  'ВАШ ВЫБОР',
                  style: TextStyle(
                    color: NonaColor.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Интернет напрямую',
                  style: TextStyle(
                    color: NonaColor.cream,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Отмеченное идёт через обычную сеть. Остальной трафик идёт через VPN. '
                  'Изменения применятся после переподключения.',
                  style: TextStyle(
                    color: NonaColor.muted,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),
                _modeCard(
                  title: 'Российские сайты напрямую',
                  description:
                      'Сайты из российских доменных зон и каталога, '
                      'включая банки и сервисы, откроются через обычную сеть.',
                  mode: policy?.sitesMode,
                  expanded: _sitesExpanded,
                  toggleDetails: () =>
                      setState(() => _sitesExpanded = !_sitesExpanded),
                  changeMode: policy == null
                      ? null
                      : (mode) => _save(policy.withSitesMode(mode)),
                  allLabel: 'Все российские сайты, банки и сервисы',
                  essentialLabel: 'Только банки и сервисы',
                  listLabel: 'Выбрать сайты',
                  openList: () => _openCategory('sites'),
                ),
                const SizedBox(height: 14),
                _modeCard(
                  title: 'Российские приложения напрямую',
                  description:
                      'Найденные приложения из каталога и с префиксом ru., '
                      'включая банки и сервисы, обойдут VPN целиком.',
                  mode: policy?.appsMode,
                  expanded: _appsExpanded,
                  toggleDetails: () =>
                      setState(() => _appsExpanded = !_appsExpanded),
                  changeMode: policy == null
                      ? null
                      : (mode) => _save(policy.withAppsMode(mode)),
                  allLabel: 'Все российские приложения, банки и сервисы',
                  essentialLabel: 'Только банки и сервисы',
                  listLabel: 'Выбрать приложения',
                  openList: () => _openCategory('russianApps'),
                ),
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    title: const Text('Свои сайты'),
                    subtitle: policy == null
                        ? const DelayedProgressIndicator(
                            message: 'Загружаем ваши сайты…',
                            compact: true,
                          )
                        : Text(
                            policy.customSites.isEmpty
                                ? 'Добавьте сайты для прямого соединения'
                                : '${policy.customSites.length} сайтов идут напрямую',
                          ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openCategory('customSites'),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    title: const Text('Приложения мимо VPN'),
                    subtitle: policy == null
                        ? const DelayedProgressIndicator(
                            message: 'Загружаем приложения…',
                            compact: true,
                          )
                        : const Text(
                            'Установленные программы и их текущий маршрут',
                          ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openCategory('apps'),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
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
          ),
        ),
      ),
    );
  }
}

typedef _SavePolicy = Future<bool> Function(InternetPolicy policy);

Widget _loadingDataArea({
  required String message,
  required String? error,
  required Future<void> Function() onRefresh,
  required VoidCallback onRetry,
}) => RefreshIndicator(
  onRefresh: onRefresh,
  child: ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16),
    children: [
      SizedBox(
        height: 180,
        child: Center(
          child: error == null
              ? DelayedProgressIndicator(message: message)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: NonaColor.muted),
                    ),
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
        ),
      ),
    ],
  ),
);

class _SiteListPage extends StatefulWidget {
  const _SiteListPage({
    required this.data,
    required this.policy,
    required this.error,
    required this.retry,
    required this.save,
  });
  final InternetRoutingState? data;
  final InternetPolicy? policy;
  final String? error;
  final Future<void> Function() retry;
  final _SavePolicy save;
  @override
  State<_SiteListPage> createState() => _SiteListPageState();
}

class _SiteListPageState extends State<_SiteListPage> {
  InternetRoutingState? _data;
  InternetPolicy? _policy;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _data = widget.data;
    _policy = widget.policy;
  }

  @override
  void didUpdateWidget(covariant _SiteListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) _data = widget.data;
    if (widget.policy != oldWidget.policy) _policy = widget.policy;
  }

  Future<void> _refresh() async {
    final data = await InternetRoutingClient().load();
    if (mounted) {
      setState(() {
        _data = data;
        _policy = data.policy;
      });
    }
  }

  Future<void> _set(RussianSite site, bool direct) async {
    final policy = _policy;
    if (policy == null) return;
    final next = policy.withSite(site, direct);
    if (await widget.save(next) && mounted) setState(() => _policy = next);
  }

  Future<void> _toggleAll(List<RussianSite> sites) async {
    final policy = _policy;
    if (sites.isEmpty || policy == null) return;
    final allSelected = sites.every(policy.directSite);
    final next = InternetPolicy(
      sitesMode: policy.sitesMode,
      appsMode: policy.appsMode,
      siteOverrides: {
        ...policy.siteOverrides,
        for (final site in sites) site.domain: !allSelected,
      },
      appOverrides: policy.appOverrides,
      customSites: policy.customSites,
    );
    if (await widget.save(next) && mounted) {
      setState(() => _policy = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final policy = _policy;
    final matchingSites = (data?.sites ?? const <RussianSite>[])
        .where(
          (site) =>
              site.label.toLowerCase().contains(_search.toLowerCase()) ||
              site.domain.contains(_search.toLowerCase()),
        )
        .toList();
    final sites = [
      ...matchingSites.where((site) => site.zone),
      ...matchingSites.where((site) => !site.zone),
    ];
    final zones = sites.where((site) => site.zone).toList();
    final services = sites.where((site) => !site.zone).toList();
    final allSelected =
        data != null &&
        policy != null &&
        data.sites.isNotEmpty &&
        data.sites.every(policy.directSite);
    return Scaffold(
      appBar: AppBar(title: const Text('Российские сайты')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Отмеченные адреса идут напрямую',
                style: TextStyle(color: NonaColor.muted, fontSize: 13),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Найти сайт',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: data == null || policy == null
                    ? null
                    : () => _toggleAll(sites),
                icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                label: Text(allSelected ? 'Снять выбор' : 'Выбрать все'),
              ),
            ),
          ),
          Expanded(
            child: data == null || policy == null
                ? _loadingDataArea(
                    message: 'Загружаем сайты и правила…',
                    error: widget.error,
                    onRefresh: _refresh,
                    onRetry: widget.retry,
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        if (zones.isNotEmpty)
                          _catalogSection(
                            'Доменные зоны',
                            zones
                                .map(
                                  (site) => _RouteToggleTile(
                                    title: site.label,
                                    subtitle:
                                        'Все сайты в зоне ${site.label.split(' ').first}',
                                    value: policy.directSite(site),
                                    onChanged: (value) => _set(site, value),
                                  ),
                                )
                                .toList(),
                          ),
                        if (services.isNotEmpty)
                          _catalogSection(
                            'Сервисы и банки',
                            services
                                .map(
                                  (site) => _RouteToggleTile(
                                    title: site.label,
                                    subtitle: site.domain,
                                    value: policy.directSite(site),
                                    onChanged: (value) => _set(site, value),
                                  ),
                                )
                                .toList(),
                          ),
                        if (sites.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Совпадений не найдено'),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Готово'),
          ),
        ),
      ),
    );
  }
}

Widget _catalogSection(String title, List<Widget> children) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: NonaColor.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: NonaColor.raised,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(children: children),
      ),
    ],
  ),
);

class _RouteToggleTile extends StatelessWidget {
  const _RouteToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$title, $subtitle',
    toggled: value,
    child: InkWell(
      onTap: () => onChanged(!value),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: NonaColor.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: NonaColor.cream,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: NonaColor.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 35,
              height: 20,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? NonaColor.coral : NonaColor.line,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Align(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: NonaColor.cream,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppListPage extends StatefulWidget {
  const _AppListPage({
    required this.data,
    required this.policy,
    required this.error,
    required this.retry,
    required this.save,
    required this.russianOnly,
  });
  final InternetRoutingState? data;
  final InternetPolicy? policy;
  final String? error;
  final Future<void> Function() retry;
  final _SavePolicy save;
  final bool russianOnly;
  @override
  State<_AppListPage> createState() => _AppListPageState();
}

class _AppListPageState extends State<_AppListPage> {
  InternetRoutingState? _data;
  InternetPolicy? _policy;
  String _search = '';
  bool _updatingAll = false;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
    _policy = widget.policy;
  }

  @override
  void didUpdateWidget(covariant _AppListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) _data = widget.data;
    if (widget.policy != oldWidget.policy) _policy = widget.policy;
  }

  Future<void> _refresh() async {
    final data = await InternetRoutingClient().load();
    if (mounted) {
      setState(() {
        _data = data;
        _policy = data.policy;
      });
    }
  }

  Future<void> _toggleAll(List<LaunchableApp> apps) async {
    final data = _data;
    final policy = _policy;
    if (_updatingAll || apps.isEmpty || data == null || policy == null) return;
    setState(() => _updatingAll = true);
    final allSelected = apps.every(
      (app) => policy.directApp(app.packageName, data.appCatalogue),
    );
    final overrides = Map<String, bool>.of(policy.appOverrides);
    for (final app in apps) {
      final id = app.packageName;
      final keepRussian =
          !widget.russianOnly &&
          allSelected &&
          (id.startsWith('ru.') || data.appCatalogue.containsKey(id)) &&
          policy.directApp(id, data.appCatalogue);
      overrides[id] = allSelected ? keepRussian : true;
    }
    final next = InternetPolicy(
      sitesMode: policy.sitesMode,
      appsMode: policy.appsMode,
      siteOverrides: policy.siteOverrides,
      appOverrides: overrides,
      customSites: policy.customSites,
    );
    try {
      if (await widget.save(next) && mounted) {
        setState(() => _policy = next);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              allSelected
                  ? 'Выбор снят. Российские приложения сохранены. Переподключите VPN, чтобы применить.'
                  : 'Отмечено приложений: ${apps.length}. Переподключите VPN, чтобы применить.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
  }

  Future<void> _set(String id, bool direct) async {
    final data = _data;
    final policy = _policy;
    if (data == null || policy == null) return;
    final next = policy.withApp(id, direct, data.appCatalogue);
    if (await widget.save(next) && mounted) setState(() => _policy = next);
  }

  Future<void> _addWindowsProcess() async {
    final data = _data;
    final policy = _policy;
    if (data == null || policy == null) return;
    var typed = '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить программу'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Имя исполняемого файла',
            hintText: 'chrome.exe',
          ),
          onChanged: (text) => typed = text,
          onSubmitted: (_) => Navigator.pop(context, typed),
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
      final name = normalizeWindowsProcessName(value);
      final next = policy.withApp(name, true, data.appCatalogue);
      if (await widget.save(next) && mounted) setState(() => _policy = next);
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final policy = _policy;
    final known = <String, LaunchableApp>{
      for (final app in data?.apps ?? const <LaunchableApp>[])
        app.packageName: app,
    };
    if (!widget.russianOnly && policy != null) {
      for (final id in policy.appOverrides.keys) {
        known.putIfAbsent(
          id,
          () => LaunchableApp(
            packageName: id,
            label: defaultTargetPlatform == TargetPlatform.windows
                ? '$id.exe (сохранено)'
                : '$id (не найдено)',
          ),
        );
      }
    }
    final apps =
        known.values.where((app) {
          final id = app.packageName;
          if (widget.russianOnly &&
              !id.startsWith('ru.') &&
              !(data?.appCatalogue.containsKey(id) ?? false)) {
            return false;
          }
          final query = _search.toLowerCase();
          return app.label.toLowerCase().contains(query) ||
              id.toLowerCase().contains(query);
        }).toList()..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
    final allSelected =
        data != null &&
        policy != null &&
        apps.isNotEmpty &&
        apps.every(
          (app) => policy.directApp(app.packageName, data.appCatalogue),
        );
    final russianApps = apps
        .where((app) => data?.appCatalogue[app.packageName]?.essential == true)
        .toList();
    final otherApps = apps.where((app) => !russianApps.contains(app)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.russianOnly ? 'Российские приложения' : 'Приложения мимо VPN',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              defaultTargetPlatform == TargetPlatform.windows
                  ? 'Показаны запущенные программы. Можно добавить закрытую программу по имени файла .exe. Отмеченные программы идут напрямую после переподключения.'
                  : widget.russianOnly
                  ? 'Отмеченные приложения идут напрямую'
                  : 'Отмеченные приложения полностью обходят VPN. Список хранится на устройстве.',
              style: const TextStyle(color: NonaColor.muted, fontSize: 13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Найти приложение',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _updatingAll || data == null || policy == null
                    ? null
                    : () => _toggleAll(apps),
                icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                label: Text(
                  _updatingAll
                      ? 'Сохраняем…'
                      : allSelected
                      ? 'Снять выбор'
                      : 'Выбрать все',
                ),
              ),
            ),
          ),
          if (defaultTargetPlatform == TargetPlatform.windows &&
              !widget.russianOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                onPressed: data == null || policy == null
                    ? null
                    : _addWindowsProcess,
                icon: const Icon(Icons.add),
                label: const Text('Добавить программу по имени .exe'),
              ),
            ),
          Expanded(
            child: data == null || policy == null
                ? _loadingDataArea(
                    message: 'Загружаем список приложений…',
                    error: widget.error,
                    onRefresh: _refresh,
                    onRetry: widget.retry,
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        if (russianApps.isNotEmpty)
                          _catalogSection(
                            'Банки и сервисы',
                            russianApps
                                .map(
                                  (app) => _RouteToggleTile(
                                    title: app.label,
                                    subtitle: app.packageName,
                                    value: policy.directApp(
                                      app.packageName,
                                      data.appCatalogue,
                                    ),
                                    onChanged: (value) =>
                                        _set(app.packageName, value),
                                  ),
                                )
                                .toList(),
                          ),
                        if (otherApps.isNotEmpty)
                          _catalogSection(
                            widget.russianOnly
                                ? 'Другие приложения каталога'
                                : 'Другие приложения',
                            otherApps
                                .map(
                                  (app) => _RouteToggleTile(
                                    title: app.label,
                                    subtitle: app.packageName,
                                    value: policy.directApp(
                                      app.packageName,
                                      data.appCatalogue,
                                    ),
                                    onChanged: (value) =>
                                        _set(app.packageName, value),
                                  ),
                                )
                                .toList(),
                          ),
                        if (apps.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Подходящие приложения не найдены'),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Готово'),
          ),
        ),
      ),
    );
  }
}

class _CustomSitesPage extends StatefulWidget {
  const _CustomSitesPage({
    required this.policy,
    required this.error,
    required this.retry,
    required this.save,
  });
  final InternetPolicy? policy;
  final String? error;
  final Future<void> Function() retry;
  final _SavePolicy save;
  @override
  State<_CustomSitesPage> createState() => _CustomSitesPageState();
}

class _CustomSitesPageState extends State<_CustomSitesPage> {
  final _client = InternetRoutingClient();
  InternetPolicy? _policy;
  String? _error;

  @override
  void initState() {
    super.initState();
    _policy = widget.policy;
  }

  @override
  void didUpdateWidget(covariant _CustomSitesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.policy != oldWidget.policy) _policy = widget.policy;
  }

  Future<void> _refresh() async {
    final data = await _client.load();
    if (mounted) setState(() => _policy = data.policy);
  }

  Future<void> _add() async {
    final policy = _policy;
    if (policy == null) return;
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
      final next = policy.withCustomSites([...policy.customSites, domain]);
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
    final policy = _policy;
    if (policy == null) return;
    final next = policy.withCustomSites(
      policy.customSites.where((item) => item != domain),
    );
    if (await widget.save(next) && mounted) setState(() => _policy = next);
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    return Scaffold(
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
            child: policy == null
                ? _loadingDataArea(
                    message: 'Загружаем ваши сайты…',
                    error: widget.error ?? _error,
                    onRefresh: _refresh,
                    onRetry: widget.retry,
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (policy.customSites.isEmpty)
                          const ListTile(title: Text('Своих сайтов пока нет')),
                        for (final domain in policy.customSites)
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
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: policy == null ? null : _add,
                  child: const Text('Добавить сайт'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
