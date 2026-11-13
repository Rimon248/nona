import 'internet_routing.dart';

class RoutingSummary {
  const RoutingSummary({
    required this.russianSites,
    required this.russianApps,
    required this.customSites,
    required this.bypassedApps,
  });

  final int russianSites;
  final int russianApps;
  final int customSites;
  final int bypassedApps;

  factory RoutingSummary.fromState(InternetRoutingState state) {
    final policy = state.policy;
    final directApps = state.apps.where(
      (app) => policy.directApp(app.packageName, state.appCatalogue),
    );
    return RoutingSummary(
      russianSites: state.sites.where(policy.directSite).length,
      russianApps: directApps
          .where(
            (app) =>
                app.packageName.startsWith('ru.') ||
                state.appCatalogue.containsKey(app.packageName),
          )
          .length,
      customSites: policy.customSites.length,
      bypassedApps: directApps.length,
    );
  }
}
