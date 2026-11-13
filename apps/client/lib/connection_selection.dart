import 'config_bundle.dart';

enum PreferredTransport { automatic, hysteria2, vlessReality }

class ConnectionNodeOption {
  const ConnectionNodeOption({
    required this.id,
    required this.country,
    required this.transports,
  });

  final String id;
  final String country;
  final Set<String> transports;

  bool supports(PreferredTransport transport) => switch (transport) {
    PreferredTransport.automatic => true,
    PreferredTransport.hysteria2 => transports.contains('hysteria2'),
    PreferredTransport.vlessReality => transports.contains('vless-reality'),
  };

  static List<ConnectionNodeOption> fromBundle(VerifiedBundle bundle) => [
    for (final raw in bundle.payload['nodes'] as List)
      ConnectionNodeOption(
        id: (raw as Map<String, dynamic>)['id'] as String,
        country: countryForEndpoint(raw['endpoint'] as String),
        transports: (raw['transports'] as List).cast<String>().toSet(),
      ),
  ];
}

/// These labels describe the two currently provisioned endpoints. New nodes
/// need their own reviewed location before the client displays a country.
String countryForEndpoint(String endpoint) => switch (endpoint.trim()) {
  '195.63.146.49' => 'Нидерланды',
  '77.232.142.209' => 'Швеция',
  _ => 'Страна не указана',
};

String flagForCountry(String country) => switch (country) {
  'Нидерланды' => '🇳🇱',
  'Швеция' => '🇸🇪',
  _ => '🌐',
};

class ConnectionPreference {
  const ConnectionPreference({
    this.nodeId,
    this.transport = PreferredTransport.automatic,
  });

  final String? nodeId;
  final PreferredTransport transport;

  List<ConnectionNodeOption> eligibleNodes(List<ConnectionNodeOption> nodes) =>
      nodeId == null
      ? nodes
      : nodes.where((node) => node.id == nodeId).toList();

  bool allowsTransport(String value) => switch (transport) {
    PreferredTransport.automatic => true,
    PreferredTransport.hysteria2 => value == 'hysteria2',
    PreferredTransport.vlessReality => value == 'vless-reality',
  };
}
