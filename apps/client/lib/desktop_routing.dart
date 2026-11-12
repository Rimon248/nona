import 'dart:convert';
import 'dart:io';

import 'package:punycoder/punycoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Domain suffixes in the Android catalogue, stored as ASCII for Xray.
const desktopRussianZones = <String, String>{
  'ru': '.ru',
  'xn--p1ai': '.рф',
  'su': '.su',
  'moscow': '.moscow',
  'tatar': '.tatar',
  'xn--80adxhks': '.москва',
};

final _domainPattern = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$');

String normalizeDesktopSite(String input) {
  final value = input.trim();
  if (value.isEmpty || value.contains(RegExp(r'\s'))) {
    throw const FormatException('Укажите домен сайта');
  }
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.host.isEmpty ||
      uri.hasPort) {
    throw const FormatException('Укажите домен или HTTPS-адрес');
  }
  final host = Uri.decodeComponent(uri.host)
      .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  final ascii = domainToAscii(host).toLowerCase();
  if (ascii.length > 253 ||
      !_domainPattern.hasMatch(ascii) ||
      RegExp(r'^\d+(\.\d+){3}$').hasMatch(ascii)) {
    throw const FormatException('Неверный домен сайта');
  }
  return ascii;
}

String normalizeWindowsProcess(String input) {
  final name = input.trim().replaceFirst(
    RegExp(r'\.exe$', caseSensitive: false),
    '',
  );
  if (name.isEmpty ||
      name.length > 128 ||
      name.contains(RegExp(r'[/\\\x00-\x1f]')) ||
      {
        'nona_client',
        'xray',
        'system',
        'svchost',
      }.contains(name.toLowerCase())) {
    throw const FormatException('Укажите имя программы без пути');
  }
  return name;
}

class DesktopRoutingPolicy {
  DesktopRoutingPolicy({
    required Set<String> directZones,
    required Set<String> directSites,
    required Set<String> vpnSites,
    required Set<String> directProcesses,
  }) : directZones = Set.unmodifiable(directZones),
       directSites = Set.unmodifiable(directSites),
       vpnSites = Set.unmodifiable(vpnSites),
       directProcesses = Set.unmodifiable(directProcesses);

  factory DesktopRoutingPolicy.defaults() => DesktopRoutingPolicy(
    directZones: desktopRussianZones.keys.toSet(),
    directSites: {},
    vpnSites: {},
    directProcesses: {},
  );

  final Set<String> directZones;
  final Set<String> directSites;
  final Set<String> vpnSites;
  final Set<String> directProcesses;

  DesktopRoutingPolicy copyWith({
    Set<String>? directZones,
    Set<String>? directSites,
    Set<String>? vpnSites,
    Set<String>? directProcesses,
  }) => DesktopRoutingPolicy(
    directZones: directZones ?? this.directZones,
    directSites: directSites ?? this.directSites,
    vpnSites: vpnSites ?? this.vpnSites,
    directProcesses: directProcesses ?? this.directProcesses,
  );

  Map<String, Object> toJson() => {
    'version': 1,
    'directZones': directZones.toList()..sort(),
    'directSites': directSites.toList()..sort(),
    'vpnSites': vpnSites.toList()..sort(),
    'directProcesses': directProcesses.toList()..sort(),
  };

  factory DesktopRoutingPolicy.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> || raw['version'] != 1) {
      throw const FormatException('Не удалось прочитать правила маршрутизации');
    }
    Set<String> values(String key, {int max = 200}) {
      final entries = raw[key];
      if (entries is! List ||
          entries.length > max ||
          entries.any((item) => item is! String)) {
        throw const FormatException('Повреждены правила маршрутизации');
      }
      return entries.cast<String>().toSet();
    }

    final zones = values('directZones', max: desktopRussianZones.length);
    final direct = values('directSites');
    final vpn = values('vpnSites');
    final processes = values('directProcesses');
    if (!desktopRussianZones.keys.toSet().containsAll(zones) ||
        direct.any((item) => normalizeDesktopSite(item) != item) ||
        vpn.any((item) => normalizeDesktopSite(item) != item) ||
        direct.intersection(vpn).isNotEmpty ||
        processes.any((item) => normalizeWindowsProcess(item) != item)) {
      throw const FormatException('Повреждены правила маршрутизации');
    }
    return DesktopRoutingPolicy(
      directZones: zones,
      directSites: direct,
      vpnSites: vpn,
      directProcesses: processes,
    );
  }
}

class DesktopRoutingStore {
  static const _key = 'nona.desktop.routing.v1';

  static Future<DesktopRoutingPolicy> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    return saved == null
        ? DesktopRoutingPolicy.defaults()
        : DesktopRoutingPolicy.fromJson(jsonDecode(saved));
  }

  static Future<void> save(DesktopRoutingPolicy policy) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, jsonEncode(policy.toJson()))) {
      throw const FileSystemException(
        'Не удалось сохранить правила маршрутизации',
      );
    }
  }
}

class WindowsProcessCatalog {
  static Future<List<String>> running() async {
    if (!Platform.isWindows) return const [];
    final result = await Process.run('tasklist', [
      '/fo',
      'csv',
      '/nh',
    ]).timeout(const Duration(seconds: 8));
    if (result.exitCode != 0) {
      throw const ProcessException(
        'tasklist',
        [],
        'Не удалось получить список программ',
        1,
      );
    }
    return parseTasklist(result.stdout as String);
  }

  static List<String> parseTasklist(String output) {
    final names = <String>{};
    for (final line in const LineSplitter().convert(output)) {
      final match = RegExp(r'^"([^"]+)"').firstMatch(line.trim());
      if (match == null) continue;
      try {
        names.add(normalizeWindowsProcess(match.group(1)!));
      } on FormatException {
        // Keep system and helper processes out of the user-facing list.
      }
    }
    return names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}
