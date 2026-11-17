import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/internet_routing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nona.app_routing.large_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('parses a large routing catalogue without changing its rules', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'getState') throw MissingPluginException();
      return {
        'apps': [
          for (var index = 0; index < 120; index++)
            {'packageName': 'example.app$index', 'label': 'App $index'},
        ],
        'siteCatalogue': <Object>[],
        'appCatalogue': <Object>[],
        'policy': {
          'sitesMode': 'off',
          'appsMode': 'off',
          'siteOverrides': <String, bool>{},
          'appOverrides': <String, bool>{'example.app5': true},
          'customSites': <String>[],
        },
      };
    });

    final state = await InternetRoutingClient(channel).load();
    expect(state.apps.length, 120);
    expect(state.policy.directApp('example.app5', state.appCatalogue), isTrue);
    expect(state.policy.directApp('example.app6', state.appCatalogue), isFalse);
  });
}
