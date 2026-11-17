import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/app_settings.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('connection picker and notification choices are independent', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows startup, close action and connection choice are saved', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final changes = <NonaSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NonaSettingsScreen(
          settings: const NonaSettings(),
          onChanged: changes.add,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Только способ подключения'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Только способ подключения'));
    await tester.pump();
    expect(changes.last.connectionPicker, ConnectionPickerMode.transport);

    await tester.ensureVisible(find.text('Запускать вместе с Windows'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Запускать вместе с Windows'));
    await tester.pump();
    expect(changes.last.windowsAutoStart, isTrue);

    await tester.ensureVisible(find.text('Скрывать окно при запуске Windows'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Скрывать окно при запуске Windows'));
    await tester.pump();
    expect(changes.last.windowsStartHidden, isTrue);

    await tester.ensureVisible(find.text('Скрыть окно, оставить VPN включённым'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Скрыть окно, оставить VPN включённым'));
    await tester.pump();
    expect(changes.last.windowsCloseAction, WindowsCloseAction.hide);
    debugDefaultTargetPlatformOverride = null;
  });
}
