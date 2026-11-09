import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/app_routing_policy.dart';

void main() {
  test('explicit direct apps are excluded; other apps remain on VPN', () {
    final policy = AppRoutingPolicy(
      ownPackage: 'org.example.nona',
      directPackages: [
        'org.example.chat',
        'org.example.bank',
        'org.example.chat',
      ],
    );
    expect(policy.directPackages, ['org.example.bank', 'org.example.chat']);
    expect(policy.usesVpn('org.example.chat'), isFalse);
    expect(policy.usesVpn('org.example.video'), isTrue);
  });

  test('never excludes the VPN app itself', () {
    expect(
      () => AppRoutingPolicy(
        ownPackage: 'org.example.nona',
        directPackages: ['org.example.nona'],
      ),
      throwsArgumentError,
    );
  });

  test('rejects ambiguous or malformed package IDs', () {
    for (final packageName in [
      'chat',
      ' org.example.chat',
      'org.example.chat/other',
    ]) {
      expect(
        () => AppRoutingPolicy(
          ownPackage: 'org.example.nona',
          directPackages: [packageName],
        ),
        throwsArgumentError,
      );
    }
  });
}
