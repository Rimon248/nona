import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/nona_startup_screen.dart';

void main() {
  late ui.Image figure;
  setUpAll(() async {
    final imageBytes = await rootBundle.load('assets/brand/nona-full-body.png');
    final codec = await ui.instantiateImageCodec(
      imageBytes.buffer.asUint8List(),
    );
    figure = (await codec.getNextFrame()).image;
    codec.dispose();
  });
  testWidgets('loading status stays in place while the dots change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: NonaStartupScreen(
          status: 'Проверяем вход и настройки',
          figure: figure,
          appVersion: '0.1.6',
        ),
      ),
    );
    final before = tester.getTopLeft(find.text('Проверяем вход и настройки'));
    await tester.pump(const Duration(milliseconds: 500));
    final after = tester.getTopLeft(find.text('Проверяем вход и настройки'));
    expect(after, before);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 780), const Size(990, 600)]) {
    testWidgets('startup screen fits ${size.width}x${size.height}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: NonaStartupScreen(
            status: 'Проверяем вход и настройки',
            figure: figure,
            appVersion: '0.1.6',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Встречаемся\nчерез мгновение.'), findsOneWidget);
      expect(find.text('Проверяем вход и настройки'), findsOneWidget);
      expect(find.text('Версия 0.1.6'), findsOneWidget);
      expect(
        (tester.getCenter(find.text('Версия 0.1.6')).dx - size.width / 2).abs(),
        lessThan(1),
      );
    });
  }
}
