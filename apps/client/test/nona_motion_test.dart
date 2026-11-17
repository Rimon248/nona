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

  testWidgets('coral dot orbits outside only while loading', (tester) async {
    Widget halo(bool loading) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: NonaConnectionHalo(
            size: 180,
            state: 'connected',
            unavailable: false,
            loading: loading,
          ),
        ),
      ),
    );
    await tester.pumpWidget(halo(false));
    final dot = find.descendant(
      of: find.byType(NonaStatusDot),
      matching: find.byType(DecoratedBox),
    );
    final start = tester.getCenter(dot);
    final ringCenter = tester.getCenter(find.byType(NonaConnectionHalo));
    expect((start - ringCenter).distance, greaterThan(90));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getCenter(dot), start);

    await tester.pumpWidget(halo(true));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final afterStart = tester.getCenter(dot);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final afterAcceleration = tester.getCenter(dot);
    expect(
      (afterAcceleration - afterStart).distance,
      greaterThan((afterStart - start).distance),
    );
    for (var frame = 0; frame < 14; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getCenter(dot), isNot(start));

    await tester.pumpWidget(halo(false));
    var previous = tester.getCenter(dot);
    final movements = <double>[];
    for (var frame = 0; frame < 200; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final current = tester.getCenter(dot);
      final distance = (current - previous).distance;
      if (distance > 0.001) movements.add(distance);
      previous = current;
      if (frame == 49) {
        expect((current - start).distance, greaterThan(1));
      }
    }
    expect((tester.getCenter(dot) - start).distance, lessThan(0.1));
    expect(movements.last, lessThan(movements.reduce((a, b) => a > b ? a : b)));
  });

  testWidgets('startup cards enter one after another', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              NonaCardSortItem(step: 0, enabled: true, child: Text('Первый')),
              NonaCardSortItem(step: 2, enabled: true, child: Text('Второй')),
            ],
          ),
        ),
      ),
    );
    final first = find.descendant(
      of: find.byType(NonaCardSortItem).at(0),
      matching: find.byType(FadeTransition),
    );
    final second = find.descendant(
      of: find.byType(NonaCardSortItem).at(1),
      matching: find.byType(FadeTransition),
    );
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.widget<FadeTransition>(first).opacity.value, greaterThan(0));
    expect(tester.widget<FadeTransition>(second).opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<FadeTransition>(first).opacity.value, 1);
    expect(tester.widget<FadeTransition>(second).opacity.value, 1);
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
