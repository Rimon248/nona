import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/nona_motion.dart';
import 'package:nona_client/nona_page_route.dart';
import 'package:nona_client/nona_control_theme.dart';

void main() {
  testWidgets('VPN indicator dot remains coral in every state', (tester) async {
    for (final state in ['idle', 'connecting', 'connected', 'disconnecting']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NonaConnectionHalo(
              size: 180,
              state: state,
              unavailable: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dots = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(NonaConnectionHalo),
              matching: find.byType(Container),
            ),
          )
          .where(
            (container) =>
                container.decoration is BoxDecoration &&
                (container.decoration! as BoxDecoration).color ==
                    NonaColor.coral,
          );
      expect(dots, isNotEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reduced motion keeps the ping state usable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(body: NonaPingWave()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Проверяем пинг'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen transition opens and closes a page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                nonaPageRoute<void>(
                  context,
                  Scaffold(
                    appBar: AppBar(),
                    body: const Text('Следующий экран'),
                  ),
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Следующий экран'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Открыть'), findsOneWidget);
  });
}
