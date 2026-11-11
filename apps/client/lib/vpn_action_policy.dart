bool canStartVpn({
  required bool busy,
  required String vpnState,
  required String? accessStatus,
  required bool hasConfiguration,
}) =>
    !busy &&
    vpnState == 'idle' &&
    hasConfiguration &&
    (accessStatus == null || accessStatus == 'approved');

String vpnActionLabel({
  required String vpnState,
  required String? accessStatus,
  required bool hasConfiguration,
}) {
  if (vpnState != 'idle') return 'Отключить';
  if (accessStatus != null && accessStatus != 'approved') {
    return 'Ожидаем доступ';
  }
  if (!hasConfiguration) return 'Ожидаем конфигурацию';
  return 'Подключить';
}
