import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/internet_routing.dart';

void main() {
  const russianZone = RussianSite(
    domain: 'ru',
    label: '.ru',
    essential: false,
    zone: true,
  );
  const bank = RussianSite(
    domain: 'sberbank.ru',
    label: 'Сбер',
    essential: true,
    zone: false,
  );
  const vk = RussianApp(packageName: 'com.vkontakte.android', essential: false);
  const govt = RussianApp(packageName: 'ru.rostel', essential: true);
  final catalogue = {vk.packageName: vk, govt.packageName: govt};

  InternetPolicy policy({
    DirectMode sites = DirectMode.off,
    DirectMode apps = DirectMode.off,
  }) => InternetPolicy(
    sitesMode: sites,
    appsMode: apps,
    siteOverrides: const {},
    appOverrides: const {},
    customSites: const [],
  );

  test('all and essential modes select different sites', () {
    expect(policy(sites: DirectMode.all).directSite(russianZone), isTrue);
    expect(
      policy(sites: DirectMode.essential).directSite(russianZone),
      isFalse,
    );
    expect(policy(sites: DirectMode.essential).directSite(bank), isTrue);
    expect(policy().directSite(bank), isFalse);
  });

  test('a site can override a broad zone and preserve its choice', () {
    final chosen = policy(sites: DirectMode.all).withSite(bank, false);
    expect(chosen.directSite(bank), isFalse);
    expect(chosen.directSite(russianZone), isTrue);
    expect(chosen.toChannel()['siteOverrides'], {'sberbank.ru': false});
  });

  test('known com packages join the all-app catalogue', () {
    final chosen = policy(apps: DirectMode.all);
    expect(chosen.directApp(vk.packageName, catalogue), isTrue);
    expect(chosen.directApp('com.unknown.app', catalogue), isFalse);
    expect(chosen.directApp('ru.some.app', catalogue), isTrue);
    expect(
      policy(apps: DirectMode.essential).directApp(vk.packageName, catalogue),
      isFalse,
    );
    expect(
      policy(apps: DirectMode.essential).directApp(govt.packageName, catalogue),
      isTrue,
    );
    expect(
      chosen
          .withApp(vk.packageName, false, catalogue)
          .directApp(vk.packageName, catalogue),
      isFalse,
    );
  });

  test('custom site accepts an HTTPS host and rejects unsafe input', () {
    expect(normalizeCustomSite('https://www.example.ru/path'), 'example.ru');
    expect(normalizeCustomSite('example.com'), 'example.com');
    expect(
      normalizeCustomSite('https://www.пример.рф/path'),
      'xn--e1afmkfd.xn--p1ai',
    );
    expect(
      () => normalizeCustomSite('http://example.ru'),
      throwsFormatException,
    );
    expect(
      () => normalizeCustomSite('https://user@example.ru'),
      throwsFormatException,
    );
    expect(() => normalizeCustomSite('192.168.1.1'), throwsFormatException);
    expect(() => normalizeCustomSite('example.ru:8443'), throwsFormatException);
  });
}
