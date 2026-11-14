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
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Встречаемся\nчерез мгновение.'), findsOneWidget);
      expect(find.text('Проверяем вход и настройки'), findsOneWidget);
    });
  }
}
