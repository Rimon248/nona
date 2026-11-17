import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/internet_routing.dart';
import 'package:nona_client/internet_routing_screen.dart';
import 'package:nona_client/nona_page_route.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nona.app_routing');

  testWidgets('routing page opens before its list is populated', (
    tester,
  ) async {
    const data = InternetRoutingState(
      apps: [],
      sites: [],
      appCatalogue: {},
      policy: InternetPolicy(
        sitesMode: DirectMode.off,
        appsMode: DirectMode.off,
        siteOverrides: {},
        appOverrides: {},
        customSites: ['example.ru'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                nonaPageRoute<void>(
                  context,
                  const InternetRoutingScreen(
                    initialCategory: 'customSites',
                    initialData: data,
                  ),
                ),
              ),
              child: const Text('Открыть маршруты'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть маршруты'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Свои сайты'), findsOneWidget);
    expect(find.text('example.ru'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('example.ru'), findsOneWidget);
  });

  testWidgets('closing the add-site dialog leaves the page usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getState') {
            return {
              'apps': <Object>[],
              'siteCatalogue': <Object>[],
              'appCatalogue': <Object>[],
              'policy': {
                'sitesMode': 'off',
                'appsMode': 'off',
                'siteOverrides': <String, bool>{},
                'appOverrides': <String, bool>{},
                'customSites': <String>[],
              },
            };
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(const MaterialApp(home: InternetRoutingScreen()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Свои сайты'));
    await tester.tap(find.text('Свои сайты'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить сайт'));
    await tester.pumpAndSettle();
    expect(find.text('Домен или HTTPS-адрес'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Своих сайтов пока нет'), findsOneWidget);
  });
}
