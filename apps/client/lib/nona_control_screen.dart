import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connection_selection.dart';
import 'delayed_progress_indicator.dart';
import 'routing_summary.dart';
import 'nona_control_theme.dart';

class NonaControlScreen extends StatelessWidget {
  const NonaControlScreen({
    super.key,
    required this.selectedTab,
    required this.onSelectTab,
    required this.vpnState,
    required this.signedIn,
    required this.accountConfigured,
    required this.actionLabel,
    required this.onAction,
    required this.onConnectionTap,
    required this.onRefresh,
    required this.busy,
    required this.measuringLatency,
    required this.onMeasureLatency,
    required this.routingAvailable,
    required this.onOpenRouting,
    required this.onOpenRouteCategory,
    required this.onLogin,
    required this.onLogout,
    required this.onRetryDevice,
    required this.configurationMessage,
    required this.nodeOptions,
    required this.selectedNodeId,
    required this.selectedTransport,
    required this.manualConnectionEnabled,
    required this.onManualConnectionChanged,
    required this.onSelectNode,
    required this.onSelectTransport,
    this.routingSummary,
    this.country,
    this.transport,
    this.latencyMs,
    this.latencyMessage,
    this.username,
    this.accessLabel,
    this.deviceRegistered = false,
  });

  final int selectedTab;
  final ValueChanged<int> onSelectTab;
  final String vpnState;
  final bool signedIn;
  final bool accountConfigured;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onConnectionTap;
  final Future<void> Function() onRefresh;
  final bool busy;
  final bool measuringLatency;
  final VoidCallback? onMeasureLatency;
  final bool routingAvailable;
  final VoidCallback? onOpenRouting;
  final ValueChanged<String>? onOpenRouteCategory;
  final VoidCallback? onLogin;
  final VoidCallback? onLogout;
  final VoidCallback? onRetryDevice;
  final String configurationMessage;
  final String? country;
  final String? transport;
  final RoutingSummary? routingSummary;
  final List<ConnectionNodeOption> nodeOptions;
  final String? selectedNodeId;
  final PreferredTransport selectedTransport;
  final bool manualConnectionEnabled;
  final ValueChanged<bool> onManualConnectionChanged;
  final ValueChanged<String?> onSelectNode;
  final ValueChanged<PreferredTransport> onSelectTransport;
  final int? latencyMs;
  final String? latencyMessage;
  final String? username;
  final String? accessLabel;
  final bool deviceRegistered;

  bool get _connected => vpnState == 'connected';

  String get _statusLabel => switch (vpnState) {
    'connected' => 'Подключено',
    'connecting' => 'Подключение',
    'disconnecting' => 'Отключение',
    'error' => 'Ошибка',
    _ => 'Не подключено',
  };

  String get _statusCaption => switch (vpnState) {
    'connected' => 'Нажмите, чтобы отключить',
    'connecting' => 'Запускаем VPN',
    'disconnecting' => 'Останавливаем VPN',
    'error' => 'Проверьте соединение',
    _ =>
      onConnectionTap == null
          ? 'Ожидаем настройки'
          : 'Нажмите, чтобы подключить',
  };

  String get _channel {
    if (!_connected) return 'Канал не выбран';
    return country ?? 'Страна не указана';
  }

  String get _connectionPreview {
    final selected = nodeOptions.where((item) => item.id == selectedNodeId);
    final location = selectedNodeId == null || selected.isEmpty
        ? 'Автоматически'
        : selected.first.country;
    final protocol = switch (selectedTransport) {
      PreferredTransport.automatic => 'Автоматически',
      PreferredTransport.hysteria2 => 'Hysteria2',
      PreferredTransport.vlessReality => 'VLESS',
    };
    return '$location · $protocol';
  }

  Widget _connectionSettings(BuildContext context) {
    if (!manualConnectionEnabled) return const SizedBox.shrink();
    final selected = nodeOptions.where((item) => item.id == selectedNodeId);
    final flag = selected.isEmpty
        ? '🌐'
        : flagForCountry(selected.first.country);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: nodeOptions.isEmpty
            ? null
            : () => _openConnectionSettings(context),
        icon: Text(flag, style: const TextStyle(fontSize: 20)),
        label: Text(
          'Подключение: $_connectionPreview',
          maxLines: 2,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Future<void> _openConnectionSettings(BuildContext context) async {
    var chosenNode = selectedNodeId;
    var chosenTransport = selectedTransport;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: NonaColor.raised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final selected = nodeOptions.where((item) => item.id == chosenNode);
          final supported = selected.isEmpty
              ? nodeOptions.expand((item) => item.transports).toSet()
              : selected.first.transports;
          Widget option(
            String title,
            String? subtitle,
            String leading,
            bool chosen,
            VoidCallback select,
          ) => ListTile(
            minTileHeight: 52,
            leading: Text(leading, style: const TextStyle(fontSize: 22)),
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: Icon(
              chosen ? Icons.radio_button_checked : Icons.radio_button_off,
              color: chosen ? NonaColor.coral : NonaColor.muted,
            ),
            selected: chosen,
            onTap: select,
          );
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Выбор подключения',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Страна сервера',
                    style: TextStyle(color: NonaColor.muted),
                  ),
                  option(
                    'Автоматически',
                    'Сначала доступный сервер',
                    '🌐',
                    chosenNode == null,
                    () {
                      setSheetState(() => chosenNode = null);
                      onSelectNode(null);
                    },
                  ),
                  for (final node in nodeOptions)
                    option(
                      node.country,
                      null,
                      flagForCountry(node.country),
                      chosenNode == node.id,
                      () {
                        setSheetState(() {
                          chosenNode = node.id;
                          if (!node.supports(chosenTransport)) {
                            chosenTransport = PreferredTransport.automatic;
                          }
                        });
                        onSelectNode(node.id);
                      },
                    ),
                  const Divider(),
                  const Text(
                    'Способ подключения',
                    style: TextStyle(color: NonaColor.muted),
                  ),
                  option(
                    'Автоматически',
                    'Hysteria2, затем VLESS',
                    '↗',
                    chosenTransport == PreferredTransport.automatic,
                    () {
                      setSheetState(
                        () => chosenTransport = PreferredTransport.automatic,
                      );
                      onSelectTransport(PreferredTransport.automatic);
                    },
                  ),
                  if (supported.contains('hysteria2'))
                    option(
                      'Hysteria2',
                      null,
                      'H',
                      chosenTransport == PreferredTransport.hysteria2,
                      () {
                        setSheetState(
                          () => chosenTransport = PreferredTransport.hysteria2,
                        );
                        onSelectTransport(PreferredTransport.hysteria2);
                      },
                    ),
                  if (supported.contains('vless-reality'))
                    option(
                      'VLESS',
                      null,
                      'V',
                      chosenTransport == PreferredTransport.vlessReality,
                      () {
                        setSheetState(
                          () =>
                              chosenTransport = PreferredTransport.vlessReality,
                        );
                        onSelectTransport(PreferredTransport.vlessReality);
                      },
                    ),
                  if (vpnState != 'idle')
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Новый выбор применится после переподключения.',
                        style: TextStyle(color: NonaColor.muted),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          setSheetState(() {
                            chosenNode = null;
                            chosenTransport = PreferredTransport.automatic;
                          });
                          onSelectNode(null);
                          onSelectTransport(PreferredTransport.automatic);
                        },
                        child: const Text('Сброс'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Готово'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String get _desktopDetailTitle => _connected
      ? 'Вы на связи'
      : vpnState == 'error'
      ? 'Нужна проверка'
      : 'Готово к подключению';

  String get _desktopDetailText => _connected
      ? routingAvailable
            ? 'Подключение работает через выбранный канал. Прямые маршруты используют обычную сеть.'
            : 'Подключение работает через выбранный канал.'
      : signedIn
      ? routingAvailable
            ? 'Нона подключит доступный канал. Прямые маршруты сохранят свой выбор.'
            : 'Нона подключит доступный канал.'
      : 'Войдите в аккаунт, чтобы Нона получила настройки этого устройства.';

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      systemNavigationBarColor: NonaColor.deep,
      systemNavigationBarDividerColor: NonaColor.deep,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
    child: Scaffold(
      backgroundColor: NonaColor.navy,
      body: LayoutBuilder(
        builder: (context, box) =>
            box.maxWidth >= 1080 ? _desktop(context) : _mobile(context),
      ),
    ),
  );

  Widget _brand({double fontSize = 23}) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: 'Нона',
          style: TextStyle(
            color: NonaColor.cream,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
          ),
        ),
        TextSpan(
          text: '.',
          style: TextStyle(
            color: NonaColor.coral,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _mobile(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: SizedBox(
              height: 42,
              child: Row(
                children: [
                  _brand(fontSize: 19),
                  const Spacer(),
                  const NonaFace(size: 32),
                ],
              ),
            ),
          ),
          Expanded(
            child: selectedTab == 0
                ? _mobileStatus(context)
                : _mobileDetail(context),
          ),
          _mobileDock(context),
        ],
      ),
    );
  }

  Widget _mobileStatus(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(26, 8, 26, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow('Состояние связи'),
            const SizedBox(height: 10),
            const Text(
              'Ваше соединение\nпод контролем.',
              style: TextStyle(
                color: NonaColor.cream,
                fontSize: 34,
                height: 1.08,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.3,
              ),
            ),
            const SizedBox(height: 30),
            Center(child: _statusRing(224)),
            const SizedBox(height: 23),
            if (manualConnectionEnabled) ...[
              _connectionSettings(context),
              const SizedBox(height: 10),
            ],
            Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: NonaColor.line),
                  bottom: BorderSide(color: NonaColor.line),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Текущий канал',
                          style: TextStyle(
                            color: NonaColor.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _channel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: NonaColor.cream,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    latencyMs == null ? '—' : '$latencyMs',
                    style: const TextStyle(
                      color: NonaColor.cream,
                      fontSize: 26,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'мс',
                    style: TextStyle(color: NonaColor.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (latencyMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  latencyMessage!,
                  style: const TextStyle(color: NonaColor.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusRing(double size) {
    return Semantics(
      button: true,
      label: _connected ? 'Отключить' : 'Подключить',
      child: InkWell(
        key: const ValueKey('connection-ring'),
        onTap: onConnectionTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF7290A1), width: 2),
                ),
              ),
              Container(
                width: size - 25,
                height: size - 25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF385A70)),
                ),
              ),
              Positioned(
                top: size * 0.02,
                right: size * 0.17,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: NonaColor.coral,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: size - 36,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _statusLabel,
                        style: const TextStyle(
                          color: NonaColor.cream,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: size - 48,
                    child: Text(
                      _statusCaption,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: NonaColor.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileDock(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      color: NonaColor.deep,
      padding: EdgeInsets.fromLTRB(18, 14, 18, bottomInset + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectedTab == 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ),
            ),
          if (selectedTab == 0) const SizedBox(height: 12),
          Row(
            children: [
              _bottomItem('Состояние', Icons.dashboard_rounded, 0),
              const SizedBox(width: 6),
              _bottomItem('Маршруты', Icons.alt_route_rounded, 1),
              const SizedBox(width: 6),
              _bottomItem('Аккаунт', Icons.person_rounded, 2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomItem(String label, IconData icon, int index) {
    final selected = selectedTab == index || (selectedTab == 3 && index == 2);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: selected ? NonaColor.raised : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => onSelectTab(index),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 62,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (selected)
                    const Positioned(
                      top: 0,
                      child: SizedBox(
                        width: 25,
                        child: Divider(
                          color: NonaColor.coral,
                          thickness: 3,
                          height: 3,
                        ),
                      ),
                    ),
                  ExcludeSemantics(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: selected ? NonaColor.coral : NonaColor.muted,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? NonaColor.cream : NonaColor.muted,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktop(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 210,
          color: NonaColor.sidebar,
          padding: const EdgeInsets.fromLTRB(20, 25, 20, 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _brand(),
              const SizedBox(height: 62),
              _sideItem('Состояние', 0),
              _sideItem('Маршруты', 1),
              _sideItem('Аккаунт', 2),
              _sideItem('Настройки', 3),
              const Spacer(),
              const Text(
                'Виртуальный помощник Нона',
                style: TextStyle(color: NonaColor.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(46, 36, 46, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.sizeOf(context).height - 68,
                ),
                child: selectedTab == 0
                    ? _desktopStatus(context)
                    : _desktopDetail(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sideItem(String label, int index) => InkWell(
    onTap: () => onSelectTab(index),
    borderRadius: BorderRadius.circular(4),
    child: Container(
      height: 48,
      width: double.infinity,
      padding: const EdgeInsets.only(left: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: selectedTab == index ? NonaColor.coral : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selectedTab == index ? NonaColor.cream : NonaColor.muted,
          fontSize: 14,
          fontWeight: selectedTab == index ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    ),
  );

  Widget _desktopHeader() => const Row(
    children: [_Eyebrow('Главная / Состояние'), Spacer(), NonaFace(size: 34)],
  );

  Widget _desktopStatus(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _desktopHeader(),
      const SizedBox(height: 18),
      const Text(
        'Соединение под контролем.',
        style: TextStyle(
          color: NonaColor.cream,
          fontSize: 35,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.3,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Нона следит за текущим каналом и покажет, когда потребуется действие.',
        style: TextStyle(color: NonaColor.muted, fontSize: 14),
      ),
      const SizedBox(height: 26),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 25),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: NonaColor.line),
                  bottom: BorderSide(color: NonaColor.line),
                ),
              ),
              child: Row(
                children: [
                  _statusRing(212),
                  const SizedBox(width: 27),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _desktopDetailTitle,
                          style: const TextStyle(
                            color: NonaColor.cream,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          _desktopDetailText,
                          style: const TextStyle(
                            color: NonaColor.muted,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 25),
                        FilledButton(
                          onPressed: onAction,
                          child: Text(actionLabel),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 34),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 30),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: NonaColor.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Eyebrow('Прямо сейчас'),
                  const SizedBox(height: 10),
                  if (manualConnectionEnabled) _connectionSettings(context),
                  _metric('Текущий канал', _channel),
                  _metric(
                    'Задержка HTTPS',
                    latencyMs == null ? '—' : '$latencyMs мс',
                    warm: latencyMs != null,
                  ),
                  _metric('Конфигурация', configurationMessage),
                  if (latencyMessage != null)
                    Text(
                      latencyMessage!,
                      style: const TextStyle(
                        color: NonaColor.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          _quickBox(
            'Сайты напрямую',
            routingAvailable
                ? 'Настроить маршруты →'
                : 'Проверить доступность →',
            1,
          ),
          const SizedBox(width: 14),
          _quickBox(
            'Приложения',
            routingAvailable
                ? 'Выбрать прямой маршрут →'
                : 'Проверить доступность →',
            1,
          ),
          const SizedBox(width: 14),
          _quickBox('Другой канал', 'Автоматический выбор →', 3),
        ],
      ),
    ],
  );

  Widget _metric(String label, String value, {bool warm = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: NonaColor.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: NonaColor.muted, fontSize: 12),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          softWrap: true,
          style: TextStyle(
            color: warm ? const Color(0xFFF3D2A0) : NonaColor.cream,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _quickBox(String title, String subtitle, int tab) => Expanded(
    child: InkWell(
      onTap: () => onSelectTab(tab),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NonaColor.raised,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: NonaColor.cream,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              softWrap: true,
              style: const TextStyle(color: NonaColor.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _mobileDetail(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: SingleChildScrollView(
      key: ValueKey('detail-$selectedTab'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(26, 8, 26, 18),
      child: _detailContent(context),
    ),
  );

  Widget _desktopDetail(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _Eyebrow(switch (selectedTab) {
            1 => 'Главная / Маршруты',
            2 => 'Главная / Аккаунт',
            _ => 'Главная / Настройки',
          }),
          const Spacer(),
          const NonaFace(size: 34),
        ],
      ),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: _detailContent(context)),
    ],
  );

  Widget _detailContent(BuildContext context) => switch (selectedTab) {
    1 => _routesContent(context),
    2 => _accountContent(context),
    _ => _settingsContent(context),
  };

  Widget _routesContent(BuildContext context) {
    final summary = routingSummary;
    Widget count(int? value, String label) => value == null
        ? const _RouteDataLoading()
        : Text(
            '$value $label',
            style: const TextStyle(color: NonaColor.muted, fontSize: 12),
          );
    Widget routeRow(String title, Widget detail, String category) => InkWell(
      onTap: routingAvailable
          ? () => onOpenRouteCategory?.call(category)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: NonaColor.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: NonaColor.cream,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  detail,
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: routingAvailable
                  ? () => onOpenRouteCategory?.call(category)
                  : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                side: const BorderSide(color: NonaColor.muted),
                foregroundColor: NonaColor.cream,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 14),
              label: const Text('Открыть'),
            ),
          ],
        ),
      ),
    );
    final leftDetail = summary == null
        ? const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Обычная сеть без VPN',
                style: TextStyle(
                  color: NonaColor.muted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              SizedBox(height: 5),
              _RouteDataLoading(compact: true),
            ],
          )
        : Text(
            'Обычная сеть без VPN\n${summary.russianSites} правил · ${summary.bypassedApps} приложений',
            style: const TextStyle(
              color: NonaColor.muted,
              fontSize: 11,
              height: 1.35,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('Ваш выбор'),
        const SizedBox(height: 8),
        const Text(
          'Пути интернета',
          style: TextStyle(
            color: NonaColor.cream,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Каждому адресу — нужный маршрут',
          style: TextStyle(color: NonaColor.muted, fontSize: 14),
        ),
        const SizedBox(height: 18),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NonaColor.raised,
                    border: const Border(
                      top: BorderSide(color: NonaColor.coral, width: 3),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Напрямую',
                        style: TextStyle(
                          color: NonaColor.cream,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      leftDetail,
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Center(
                child: Text(
                  '⇄',
                  style: TextStyle(color: NonaColor.coral, fontSize: 20),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NonaColor.raised,
                    border: const Border(
                      top: BorderSide(color: NonaColor.cream, width: 3),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Через VPN',
                        style: TextStyle(
                          color: NonaColor.cream,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Остальной трафик\nАвтоматический канал Ноны',
                        style: TextStyle(
                          color: NonaColor.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        const _Eyebrow('Правила прямого пути'),
        routeRow(
          'Российские сайты',
          count(summary?.russianSites, 'правил · домены, банки и сервисы'),
          'sites',
        ),
        routeRow(
          'Российские приложения',
          count(summary?.russianApps, 'приложений на устройстве'),
          'russianApps',
        ),
        routeRow(
          'Свои сайты',
          count(summary?.customSites, 'доменов добавлено'),
          'customSites',
        ),
        routeRow(
          'Приложения мимо VPN',
          count(summary?.bypassedApps, 'приложений в списке'),
          'apps',
        ),
        const SizedBox(height: 14),
        const Text(
          'Изменения начнут работать после переподключения.',
          style: TextStyle(color: NonaColor.muted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _accountContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Eyebrow('Личный доступ'),
      const SizedBox(height: 8),
      const Text(
        'Аккаунт',
        style: TextStyle(
          color: NonaColor.cream,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 14),
      if (!accountConfigured)
        const Text(
          'Адрес сервера аккаунтов ещё не настроен.',
          style: TextStyle(color: NonaColor.muted, fontSize: 15),
        )
      else if (!signedIn) ...[
        const Text(
          'Войдите, чтобы Нона получила настройки устройства.',
          style: TextStyle(color: NonaColor.muted, fontSize: 15),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: busy ? null : onLogin,
          child: const Text('Войти через Нону'),
        ),
      ] else ...[
        _detailRow('Имя пользователя', username ?? 'Пользователь'),
        _detailRow('Доступ', accessLabel ?? 'Проверяем доступ'),
        _detailRow(
          'Устройство',
          deviceRegistered ? 'Зарегистрировано' : 'Ожидает регистрации',
        ),
        _detailRow('Конфигурация', configurationMessage),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Выбор подключения на главной'),
          subtitle: const Text(
            'Если выключено, Нона всегда выбирает сервер и способ автоматически.',
          ),
          value: manualConnectionEnabled,
          onChanged: onManualConnectionChanged,
        ),
        if (!deviceRegistered) ...[
          const SizedBox(height: 12),
          const Text(
            'Привязка устройства нужна для получения его личной конфигурации. Если сервер был временно недоступен, попробуйте ещё раз.',
            style: TextStyle(color: NonaColor.muted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: busy ? null : onLogin,
            child: const Text('Войти через Нону'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: busy ? null : onRetryDevice,
            child: const Text('Повторить привязку устройства'),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onLogout,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFBDB3),
              side: const BorderSide(color: NonaColor.coral),
              minimumSize: const Size(0, 50),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Выйти из аккаунта'),
          ),
        ),
      ],
      if (busy) ...[
        const SizedBox(height: 20),
        const LinearProgressIndicator(),
      ],
    ],
  );

  Widget _settingsContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Eyebrow('Устройство и данные'),
      const SizedBox(height: 12),
      const Text(
        'Настройки',
        style: TextStyle(
          color: NonaColor.cream,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 14),
      _detailRow('Конфигурация', configurationMessage),
      const SizedBox(height: 18),
      const Text(
        'При подключении система запрашивает разрешение на VPN и показывает его состояние.',
        style: TextStyle(color: NonaColor.muted, fontSize: 14, height: 1.5),
      ),
    ],
  );

  Widget _detailRow(String title, String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: NonaColor.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: NonaColor.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: NonaColor.cream,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: NonaColor.muted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
    ),
  );
}

class _RouteDataLoading extends StatelessWidget {
  const _RouteDataLoading({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => DelayedProgressIndicator(
    message: compact ? 'Загрузка…' : 'Загружаем…',
    compact: compact,
  );
}
