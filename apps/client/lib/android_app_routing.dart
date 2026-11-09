import 'package:flutter/services.dart';

import 'app_routing_policy.dart';

class LaunchableApp {
  const LaunchableApp({required this.packageName, required this.label});
  final String packageName;
  final String label;
}

class AndroidRoutingState {
  const AndroidRoutingState({
    required this.ownPackage,
    required this.apps,
    required this.policy,
  });

  final String ownPackage;
  final List<LaunchableApp> apps;
  final AppRoutingPolicy policy;
}

class AndroidAppRouting {
  AndroidAppRouting([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('nona.app_routing');

  final MethodChannel _channel;

  Future<AndroidRoutingState> load() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getState');
    if (raw == null ||
        raw['ownPackage'] is! String ||
        raw['directPackages'] is! List ||
        raw['apps'] is! List) {
      throw const FormatException('Invalid Android routing response');
    }
    final ownPackage = raw['ownPackage'] as String;
    final directPackages = (raw['directPackages'] as List).cast<String>();
    final apps = <LaunchableApp>[];
    for (final item in raw['apps'] as List) {
      if (item is! Map ||
          item['packageName'] is! String ||
          item['label'] is! String) {
        throw const FormatException('Invalid Android app entry');
      }
      apps.add(
        LaunchableApp(
          packageName: item['packageName'] as String,
          label: item['label'] as String,
        ),
      );
    }
    return AndroidRoutingState(
      ownPackage: ownPackage,
      apps: apps,
      policy: AppRoutingPolicy(
        ownPackage: ownPackage,
        directPackages: directPackages,
      ),
    );
  }

  Future<void> save(String ownPackage, Iterable<String> directPackages) async {
    final policy = AppRoutingPolicy(
      ownPackage: ownPackage,
      directPackages: directPackages,
    );
    await _channel.invokeMethod<void>('saveDirectPackages', {
      'packages': policy.directPackages,
    });
  }
}
