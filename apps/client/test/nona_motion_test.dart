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
      await tester.pump(const Duration(milliseconds: 220));
      final dots = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(NonaConnectionHalo),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).color == NonaColor.coral,
          );
      expect(dots, isNotEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('coral dot travels along the connection ring', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: NonaConnectionHalo(
              size: 180,
              state: 'connected',
              unavailable: false,
            ),
          ),
        ),
      ),
    );
    final dot = find.descendant(
      of: find.byType(NonaStatusDot),
      matching: find.byType(DecoratedBox),
    );
    final start = tester.getCenter(dot);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.getCenter(dot), isNot(start));
  });

  testWidgets('VPN circle compresses and springs back on press', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: NonaConnectionPress(
              enabled: true,
              child: ColoredBox(
                color: Colors.black,
                child: SizedBox(width: 180, height: 180),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(NonaConnectionPress)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final press = find.descendant(
      of: find.byType(NonaConnectionPress),
      matching: find.byType(ScaleTransition),
    );
    expect(tester.widget<ScaleTransition>(press).scale.value, lessThan(1));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<ScaleTransition>(press).scale.value,
      closeTo(1, 0.001),
    );
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
