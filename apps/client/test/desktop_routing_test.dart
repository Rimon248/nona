import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/desktop_routing.dart';

void main() {
  test('site names and process names are normalized for Xray', () {
    expect(normalizeDesktopSite('https://www.рефлаб.рф/'), 'xn--80ackyxz.xn--p1ai');
    expect(normalizeDesktopSite('example.ru'), 'example.ru');
    expect(() => normalizeDesktopSite('http://example.ru'), throwsFormatException);
    expect(normalizeWindowsProcess('chrome.exe'), 'chrome');
    expect(() => normalizeWindowsProcess('C:/Windows/System32/curl.exe'), throwsFormatException);
  });

  test('desktop policy preserves custom route selections', () {
    final policy = DesktopRoutingPolicy.defaults().copyWith(
      vpnSites: {'youtube.ru'},
      directSites: {'example.com'},
      directProcesses: {'chrome'},
    );
    final saved = DesktopRoutingPolicy.fromJson(policy.toJson());
    expect(saved.directZones, contains('xn--p1ai'));

    expect(saved.vpnSites, contains('youtube.ru'));
    expect(saved.directSites, contains('example.com'));
    expect(saved.directProcesses, contains('chrome'));
  });

  test('running Windows process list omits helper and system processes', () {
    final names = WindowsProcessCatalog.parseTasklist(
      '"chrome.exe","123","Console","1","10 K"\r\n'
      '"svchost.exe","321","Services","0","1 K"\r\n'
      '"Telegram.exe","222","Console","1","15 K"\r\n',
    );
    expect(names, ['chrome', 'Telegram']);
  });
}
