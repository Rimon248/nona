import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nona_control_theme.dart';
import 'nona_motion.dart';

/// Full-screen update offer shown between startup and the main application.
class NonaUpdateScreen extends StatefulWidget {
  const NonaUpdateScreen({
    super.key,
    required this.installedVersion,
    required this.availableVersion,
    required this.android,
    required this.cardSortEntrance,
    required this.busy,
    required this.onLater,
    required this.onUpdate,
    this.error,
  });

  final String installedVersion;
  final String availableVersion;
  final bool android;
  final bool cardSortEntrance;
  final bool busy;
  final VoidCallback onLater;
  final VoidCallback onUpdate;
  final String? error;

  @override
  State<NonaUpdateScreen> createState() => _NonaUpdateScreenState();
}

class _NonaUpdateScreenState extends State<NonaUpdateScreen>
    with TickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );
  late final Animation<double> _foregroundOpacity =
      Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(
          parent: _exit,
          curve: const Interval(0, .72, curve: Curves.easeInOutCubic),
        ),
      );
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _flow.stop();
    } else if (!_closing && !_flow.isAnimating) {
      _flow.repeat();
    }
  }

  void _close() {
    if (_closing || widget.busy) return;
    _closing = true;
    _flow.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onLater();
      return;
    }
    _exit.forward().whenComplete(() {
      // Paint the fully navy frame before the main screen enters.
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (mounted) widget.onLater();
      });
    });
  }

  @override
  void dispose() {
    _flow.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: NonaColor.deep,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final mobile = w < 700 || h > w;
        final scale = mobile
            ? math.min(w / 390, h / 780)
            : math.min(w / 990, h / 600);
        final top = math.max(
          MediaQuery.paddingOf(context).top + 12 * scale,
          (mobile ? 29 : 40) * scale,
        );
        final bottom = MediaQuery.paddingOf(context).bottom + 24 * scale;
        final left = (mobile ? 27 : 52) * scale;
        final right = mobile ? left : w * .53;

        Widget item(int step, Widget child) => NonaCardSortItem(
          step: step,
          enabled: widget.cardSortEntrance,
          child: child,
        );

        Widget versionBlock({
          required String caption,
          required String version,
          required String detail,
          required Color textColor,
          required Color secondaryColor,
          required double versionSize,
        }) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              caption,
              style: TextStyle(
                color: secondaryColor,
                fontSize: (mobile ? 14 : 18) * scale,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: (mobile ? 18 : 25) * scale),
            Text(
              version,
              style: TextStyle(
                color: textColor,
                fontSize: versionSize * scale,
                fontWeight: FontWeight.w700,
                height: 1,
                letterSpacing: -3 * scale,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(height: (mobile ? 15 : 24) * scale),
            Text(
              detail,
              style: TextStyle(
                color: secondaryColor,
                fontSize: (mobile ? 15 : 18) * scale,
                height: 1.3,
              ),
            ),
          ],
        );

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ColorFlowPainter(mobile, _flow, _exit),
                ),
              ),
            ),
            Positioned.fill(
              child: FadeTransition(
                opacity: _foregroundOpacity,
                child: Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: top,
                      child: Text.rich(
                        TextSpan(
                          text: 'Нона',
                          children: const [
                            TextSpan(
                              text: '.',
                              style: TextStyle(color: NonaColor.coral),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          color: NonaColor.cream,
                          fontSize: (mobile ? 25 : 27) * scale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Positioned(
                      right: (mobile ? 23 : 45) * scale,
                      top: top - 7 * scale,
                      child: TextButton(
                        onPressed: widget.busy || _closing ? null : _close,
                        style: TextButton.styleFrom(
                          foregroundColor: mobile
                              ? NonaColor.muted
                              : NonaColor.deep,
                          disabledForegroundColor: NonaColor.muted,
                        ),
                        child: Text(
                          'Позже',
                          style: TextStyle(fontSize: 17 * scale),
                        ),
                      ),
                    ),
                    Positioned(
                      left: left,
                      top: h * (mobile ? .205 : .34),
                      child: item(
                        0,
                        versionBlock(
                          caption: 'СЕЙЧАС',
                          version: widget.installedVersion,
                          detail: 'Установлена на устройстве',
                          textColor: NonaColor.cream,
                          secondaryColor: NonaColor.muted,
                          versionSize: mobile ? 64 : 105,
                        ),
                      ),
                    ),
                    Positioned(
                      left: mobile ? left : right,
                      top: h * (mobile ? .52 : .34),
                      right: mobile ? left : 24 * scale,
                      child: item(
                        1,
                        versionBlock(
                          caption: 'НОВАЯ ВЕРСИЯ',
                          version: widget.availableVersion,
                          detail: mobile
                              ? 'Доступно обновление Ноны.\nНастройки сохранятся.'
                              : 'Обновление готово. Настройки сохранятся.',
                          textColor: NonaColor.deep,
                          secondaryColor: NonaColor.deep,
                          versionSize: mobile ? 72 : 105,
                        ),
                      ),
                    ),
                    if (widget.error != null)
                      Positioned(
                        left: mobile ? left : right,
                        right: mobile ? left : 42 * scale,
                        bottom: bottom + (mobile ? 69 : 76) * scale,
                        child: Text(
                          widget.error!,
                          style: TextStyle(
                            color: NonaColor.deep,
                            fontSize: (mobile ? 13 : 16) * scale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Positioned(
                      left: mobile ? left : right,
                      right: mobile ? left : 50 * scale,
                      bottom: bottom,
                      child: item(
                        2,
                        FilledButton(
                          onPressed: widget.busy || _closing
                              ? null
                              : widget.onUpdate,
                          style: FilledButton.styleFrom(
                            backgroundColor: NonaColor.cream,
                            foregroundColor: NonaColor.deep,
                            minimumSize: Size(0, (mobile ? 52 : 57) * scale),
                          ),
                          child: Text(
                            widget.busy
                                ? 'Скачиваем обновление…'
                                : widget.android
                                ? 'Скачать и установить'
                                : 'Открыть выпуск',
                            style: TextStyle(
                              fontSize: (mobile ? 16 : 18) * scale,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Curved colour bands flow slowly while the screen is open. During dismissal
/// their centre travels off-screen, leaving the old navy version behind.
class _ColorFlowPainter extends CustomPainter {
  _ColorFlowPainter(this.mobile, this.flow, this.exit)
    : super(repaint: Listenable.merge([flow, exit]));

  final bool mobile;
  final Animation<double> flow;
  final Animation<double> exit;

  static const _stops = <Color>[
    NonaColor.deep,
    Color(0xFF193D5D),
    Color(0xFF63446C),
    Color(0xFFB15368),
    NonaColor.coral,
  ];
  static const _alternateStops = <Color>[
    NonaColor.deep,
    Color(0xFF204861),
    Color(0xFF784267),
    Color(0xFFC45B65),
    NonaColor.coral,
  ];

  Color _color(double t, double phase) {
    final segment = math.min((t * 4).floor(), 3);
    final original = Color.lerp(
      _stops[segment],
      _stops[segment + 1],
      t * 4 - segment,
    )!;
    final alternate = Color.lerp(
      _alternateStops[segment],
      _alternateStops[segment + 1],
      t * 4 - segment,
    )!;
    final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
    return Color.lerp(original, alternate, pulse)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = NonaColor.deep);
    const bands = 56;
    final phase = flow.value;
    final progress = Curves.easeInOutCubic.transform(exit.value);
    final initialCenter = mobile ? size.height * .44 : size.width * .48;
    final breadth = mobile ? size.height * .15 : size.width * .18;
    final dimension = mobile ? size.height : size.width;
    final drift = math.sin(phase * math.pi * 2) * dimension * .013;
    final center =
        (initialCenter + drift) * (1 - progress) +
        (dimension + breadth) * progress;
    for (var index = 0; index <= bands; index++) {
      final t = index / bands;
      final boundary = center - breadth / 2 + breadth * t;
      final path = Path();
      if (mobile) {
        for (var part = 0; part <= 18; part++) {
          final x = size.width * part / 18;
          final wave =
              (math.sin(
                        x / size.width * math.pi * 1.4 +
                            .5 +
                            phase * math.pi * 2,
                      ) *
                      size.height *
                      .018 +
                  math.sin(
                        x / size.width * math.pi * 3.2 - phase * math.pi * 4,
                      ) *
                      size.height *
                      .005) *
              (1 - progress);
          if (part == 0) {
            path.moveTo(x, boundary + wave);
          } else {
            path.lineTo(x, boundary + wave);
          }
        }
        path
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height);
      } else {
        for (var part = 0; part <= 18; part++) {
          final y = size.height * part / 18;
          final wave =
              (math.sin(
                        y / size.height * math.pi * 1.35 +
                            .4 +
                            phase * math.pi * 2,
                      ) *
                      size.width *
                      .023 +
                  math.sin(
                        y / size.height * math.pi * 3.1 - phase * math.pi * 4,
                      ) *
                      size.width *
                      .005) *
              (1 - progress);
          if (part == 0) {
            path.moveTo(boundary + wave, y);
          } else {
            path.lineTo(boundary + wave, y);
          }
        }
        path
          ..lineTo(size.width, size.height)
          ..lineTo(size.width, 0);
      }
      canvas.drawPath(path..close(), Paint()..color = _color(t, phase));
    }
  }

  @override
  bool shouldRepaint(covariant _ColorFlowPainter oldDelegate) =>
      oldDelegate.mobile != mobile ||
      oldDelegate.flow != flow ||
      oldDelegate.exit != exit;
}
