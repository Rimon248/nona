import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/vpn_action_policy.dart';

void main() {
  test('approved account waits for a verified configuration', () {
    expect(
      canStartVpn(
        busy: false,
        vpnState: 'idle',
        accessStatus: 'approved',
        hasConfiguration: false,
      ),
      isFalse,
    );
    expect(
      vpnActionLabel(
        vpnState: 'idle',
        accessStatus: 'approved',
        hasConfiguration: false,
      ),
      'Ожидаем конфигурацию',
    );
    expect(
      canStartVpn(
        busy: false,
        vpnState: 'idle',
        accessStatus: 'approved',
        hasConfiguration: true,
      ),
      isTrue,
    );
  });

  test('pending and revoked access cannot start VPN', () {
    for (final status in ['pending', 'revoking', 'denied', 'deleting']) {
      expect(
        canStartVpn(
          busy: false,
          vpnState: 'idle',
          accessStatus: status,
          hasConfiguration: true,
        ),
        isFalse,
      );
    }
  });
}
