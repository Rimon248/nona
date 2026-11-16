import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/app_settings.dart';

void main() {
  testWidgets('connection picker and notification choices are independent', (
    tester,
  ) async {
    final changes = <NonaSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NonaSettingsScreen(
          settings: const NonaSettings(),
          onChanged: changes.add,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Только страна сервера'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Только страна сервера'));
    await tester.pump();
    expect(changes.last.connectionPicker, ConnectionPickerMode.country);
    await tester.ensureVisible(find.text('Проверка пинга в уведомлении'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проверка пинга в уведомлении'));
    await tester.pump();
    expect(changes.last.connectionPicker, ConnectionPickerMode.country);
    expect(changes.last.pingAction, true);
  });
}
