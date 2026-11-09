/// Per-app direct routing is supported by Android VpnService. This policy is
/// deliberately independent of UI labels and never infers a route from a
/// company's country or an app's name.
class AppRoutingPolicy {
  AppRoutingPolicy({
    required String ownPackage,
    required Iterable<String> directPackages,
  }) : directPackages = _validate(ownPackage, directPackages);

  static final _packageName = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$',
  );

  /// The exact installed Android package IDs that must bypass the VPN.
  final List<String> directPackages;

  bool usesVpn(String packageName) => !directPackages.contains(packageName);

  static List<String> _validate(String ownPackage, Iterable<String> packages) {
    if (!_packageName.hasMatch(ownPackage)) {
      throw ArgumentError.value(ownPackage, 'ownPackage', 'Invalid package ID');
    }
    final result = <String>{};
    for (final packageName in packages) {
      if (!_packageName.hasMatch(packageName) || packageName == ownPackage) {
        throw ArgumentError.value(
          packageName,
          'directPackages',
          'Invalid or own package ID',
        );
      }
      result.add(packageName);
    }
    return (result.toList()..sort());
  }
}
