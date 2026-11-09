import 'package:flutter/material.dart';

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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
              Text('Виртуальный Помощник Нона',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Клиент VPN для ваших устройств',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.pause_circle_outline, color: scheme.primary),
                        const SizedBox(width: 12),
                        Text('Соединение не настроено',
                            style: Theme.of(context).textTheme.titleLarge),
                      ]),
                      const SizedBox(height: 16),
                      const Text(
                        'Это каркас приложения. Вход в аккаунт, получение '
                        'индивидуальных конфигураций и VPN-подключение будут '
                        'доступны после установки серверной части и системных '
                        'модулей для каждой платформы.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('Конфигурации'),
                  subtitle: Text('На этом устройстве пока не сохранены'),
                ),
              ),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.route_outlined),
                  title: Text('Маршрутизация'),
                  subtitle: Text('Правила появятся после синхронизации'),
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
