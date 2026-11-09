import 'package:flutter/material.dart';

import 'android_app_routing.dart';

class AndroidAppRoutingScreen extends StatefulWidget {
  const AndroidAppRoutingScreen({super.key});

  @override
  State<AndroidAppRoutingScreen> createState() =>
      _AndroidAppRoutingScreenState();
}

class _AndroidAppRoutingScreenState extends State<AndroidAppRoutingScreen> {
  final _routing = AndroidAppRouting();
  AndroidRoutingState? _state;
  Set<String> _directPackages = {};
  String _search = '';
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await _routing.load();
      if (!mounted) return;
      setState(() {
        _state = state;
        _directPackages = state.policy.directPackages.toSet();
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось получить список приложений';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final state = _state;
    if (state == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _routing.save(state.ownPackage, _directPackages);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Правила сохранены для будущего VPN-подключения'),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось сохранить правила');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final known = <String, LaunchableApp>{};
    for (final app in state?.apps ?? <LaunchableApp>[]) {
      known[app.packageName] = app;
    }
    for (final id in _directPackages) {
      known.putIfAbsent(
        id,
        () => LaunchableApp(packageName: id, label: '$id (не найдено)'),
      );
    }
    final visible =
        known.values.where((app) {
          final query = _search.toLowerCase();
          return app.label.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query);
        }).toList()..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Прямое соединение')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : state == null
          ? Center(child: Text(_error ?? 'Список приложений недоступен'))
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    'Отмеченные приложения будут обходить VPN целиком, '
                    'включая работу в фоне. Пока VPN-ядро не подключено, '
                    'это сохранённая настройка без влияния на трафик. '
                    'Здесь показаны приложения с иконкой запуска.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Найти приложение',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final app = visible[index];
                      return CheckboxListTile(
                        title: Text(app.label),
                        subtitle: Text(app.packageName),
                        value: _directPackages.contains(app.packageName),
                        onChanged: _saving
                            ? null
                            : (selected) {
                                setState(() {
                                  if (selected == true) {
                                    _directPackages.add(app.packageName);
                                  } else {
                                    _directPackages.remove(app.packageName);
                                  }
                                });
                              },
                      );
                    },
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
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: const Text('Сохранить правила'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
