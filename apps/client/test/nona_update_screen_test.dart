import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/nona_update_screen.dart';

void main() {
  for (final size in [const Size(390, 780), const Size(990, 600)]) {
    testWidgets('full-screen update fits ${size.width}x${size.height}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var later = false;
      var update = false;
      await tester.pumpWidget(
        MaterialApp(
          home: NonaUpdateScreen(
            installedVersion: '0.1.6',
            availableVersion: '0.1.7',
            android: size.width < 700,
            cardSortEntrance: false,
            busy: false,
            onLater: () => later = true,
            onUpdate: () => update = true,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('0.1.6'), findsOneWidget);
      expect(find.text('0.1.7'), findsOneWidget);
      await tester.tap(
        find.text(size.width < 700 ? 'Скачать и установить' : 'Открыть выпуск'),
      );
      expect(update, isTrue);
      await tester.tap(find.text('Позже'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(later, isTrue);
    });
  }

  testWidgets('Later waits for the colour wipe before opening the app', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var later = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NonaUpdateScreen(
          installedVersion: '0.1.6',
          availableVersion: '0.1.7',
          android: true,
          cardSortEntrance: false,
          busy: false,
          onLater: () => later = true,
          onUpdate: () {},
        ),
      ),
    );

    await tester.tap(find.text('Позже'));
    await tester.pump();
    expect(later, isFalse);
    await tester.pump(const Duration(milliseconds: 600));
    expect(later, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(later, isTrue);
  });
}
