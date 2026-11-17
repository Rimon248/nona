import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/app_settings.dart';
import 'package:nona_client/connection_selection.dart';
import 'package:nona_client/nona_control_screen.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('desktop settings is a separate scrollable page', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var selectedTab = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) => NonaControlScreen(
            selectedTab: selectedTab,
            previousTab: 0,
            cardSortEntrance: false,
            onSelectTab: (tab) => update(() => selectedTab = tab),
            vpnState: 'idle',
            signedIn: false,
            accountConfigured: false,
            actionLabel: 'Войти',
            onAction: null,
            onConnectionTap: null,
            onRefresh: () async {},
            busy: false,
            measuringLatency: false,
            onMeasureLatency: null,
            routingAvailable: false,
            onOpenRouting: null,
            onOpenRouteCategory: null,
            onLogin: null,
            onLogout: null,
            onRetryDevice: null,
            configurationMessage: '',
            nodeOptions: const [],
            selectedNodeId: null,
            selectedTransport: PreferredTransport.automatic,
            manualConnectionEnabled: false,
            onManualConnectionChanged: (_) {},
            onSelectNode: (_) {},
            onSelectTransport: (_) {},
            onOpenSettings: () => update(() => selectedTab = 3),
            settingsContent: NonaSettingsScreen(
              settings: const NonaSettings(),
              embedded: true,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(selectedTab, 3);
    await tester.ensureVisible(
      find.text('Скрыть окно, оставить VPN включённым'),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Скрыть окно, оставить VPN включённым')).dy,
      lessThan(500),
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
