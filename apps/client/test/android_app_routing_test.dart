import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/android_app_routing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nona.app_routing.test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('loads and saves direct-route packages in stable order', () async {
    List<String>? saved;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getState') {
        return {
          'ownPackage': 'org.example.nona',
          'directPackages': ['org.example.chat'],
          'apps': [
            {'packageName': 'org.example.chat', 'label': 'Chat'},
            {'packageName': 'org.example.bank', 'label': 'Bank'},
          ],
        };
      }
      if (call.method == 'saveDirectPackages') {
        saved = (call.arguments as Map)['packages'].cast<String>();
        return null;
      }
      throw MissingPluginException();
    });
    final routing = AndroidAppRouting(channel);
    final state = await routing.load();
    expect(state.policy.usesVpn('org.example.chat'), isFalse);
    expect(state.apps.length, 2);
    await routing.save(state.ownPackage, [
      'org.example.chat',
      'org.example.bank',
      'org.example.chat',
    ]);
    expect(saved, ['org.example.bank', 'org.example.chat']);
  });

  test(
    'rejects an attempt to exclude Nona itself before native call',
    () async {
      final routing = AndroidAppRouting(channel);
      await expectLater(
        routing.save('org.example.nona', ['org.example.nona']),
        throwsArgumentError,
      );
    },
  );
}
