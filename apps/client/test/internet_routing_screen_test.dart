import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/internet_routing_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nona.app_routing');

  testWidgets('closing the add-site dialog leaves the page usable', (
    tester,
  ) async {
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
