import 'auth_client.dart';
import 'config_bundle.dart';
import 'configuration_vault.dart';

/// Fetches one device's signed update and saves it only after verification.
/// A 404 means the server has withdrawn or has not issued a configuration;
/// network failures leave the last locally verified bundle untouched.
class ConfigurationSync {
  const ConfigurationSync(this.auth, this.vault);

  final AuthClient auth;
  final ConfigurationVault vault;

  Future<VerifiedBundle?> refresh({
    required String deviceId,
    required DateTime now,
  }) async {
    final accountId = auth.accountId;
    if (accountId == null) throw const AuthException('Sign in required');
    final envelope = await auth.fetchConfiguration(deviceId);
    if (envelope == null) {
      await vault.clear();
      return null;
    }
    return vault.accept(
      envelope,
      accountId: accountId,
      deviceId: deviceId,
      now: now,
    );
  }
}
