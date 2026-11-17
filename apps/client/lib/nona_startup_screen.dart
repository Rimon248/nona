import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'nona_control_theme.dart';
import 'nona_motion.dart';

/// The same composition as the approved phone and desktop loading mockups.
class NonaStartupScreen extends StatefulWidget {
  const NonaStartupScreen({super.key, required this.status, this.figure});

  final String status;
  final ui.Image? figure;

  @override
  State<NonaStartupScreen> createState() => _NonaStartupScreenState();
}

class _NonaStartupScreenState extends State<NonaStartupScreen> {
  final ValueNotifier<int> _activeDot = ValueNotifier(0);
  Timer? _dotTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _dotTimer?.cancel();
      _dotTimer = null;
      if (_activeDot.value != 0) _activeDot.value = 0;
    } else {
      _dotTimer ??= Timer.periodic(const Duration(milliseconds: 450), (_) {
        _activeDot.value = (_activeDot.value + 1) % 3;
      });
    }
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    _activeDot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NonaColor.navy,
      body: LayoutBuilder(
        builder: (context, size) {
          final w = size.maxWidth;
          final h = size.maxHeight;
          final mobile = w < 700 || h > w;
          final scale = mobile
              ? math.min(w / 390, h / 780)
              : math.min(w / 990, h / 600);
          final topInset = MediaQuery.paddingOf(context).top;
          final brandX = mobile ? 27.0 * scale : 56.0 * scale;
          final brandY = math.max(
            topInset + 12,
            (mobile ? 23.0 : 43.0) * scale,
          );
          final figureHeight = (mobile ? 465.0 : 550.0) * scale;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _DiagonalPanel(mobile)),
              ),
              Positioned(
                left: mobile ? 34 * scale : w - (424 * scale),
                top: mobile ? 137 * scale : (h - 600 * scale) / 2 + 43 * scale,
                height: figureHeight,
                child: widget.figure == null
                    ? Image.asset(
                        'assets/brand/nona-full-body.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      )
                    : RawImage(
                        image: widget.figure,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
              ),
              Positioned(
                left: brandX,
                top: brandY,
                child: _Brand(scale: scale, mobile: mobile),
              ),
              Positioned(
                left: mobile ? 28 * scale : 70 * scale,
                top: mobile ? h - 166 * scale : h / 2 - 31 * scale,
                child: Text(
                  'Встречаемся\nчерез мгновение.',
                  style: TextStyle(
                    fontSize: (mobile ? 30 : 47) * scale,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                    color: NonaColor.cream,
                  ),
                ),
              ),
              Positioned(
                left: mobile ? 31 * scale : 73 * scale,
                top: mobile ? h - 70 * scale : h / 2 + 142 * scale,
                right: mobile ? 10 * scale : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: _activeDot,
                      builder: (context, active, _) {
                        final dotSize = (mobile ? 10.0 : 12.0) * scale;
                        final spacing = 6 * scale;
                        return SizedBox(
                          width: dotSize * 3 + spacing * 2,
                          child: Row(
                            children: List.generate(
                              3,
                              (index) => Padding(
                                padding: EdgeInsets.only(
                                  right: index == 2 ? 0 : spacing,
                                ),
                                child: AnimatedContainer(
                                  duration: NonaMotion.duration(
                                    context,
                                    NonaMotion.quick,
                                  ),
                                  width: dotSize,
                                  height: dotSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: index == active
                                        ? NonaColor.coral
                                        : NonaColor.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(width: (mobile ? 12 : 25) * scale),
                    Flexible(
                      child: Text(
                        widget.status,
                        maxLines: 2,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: (mobile ? 14 : 19) * scale,
                          color: NonaColor.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.scale, required this.mobile});

  final double scale;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final size = (mobile ? 22.0 : 27.0) * scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final word in ['Виртуальный', 'Помощник', 'Нона.'])
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: size,
                height: mobile ? 1.23 : 1.22,
                fontWeight: FontWeight.w700,
                color: NonaColor.cream,
              ),
              children: [
                TextSpan(
                  text: word.substring(0, 1),
                  style: const TextStyle(color: NonaColor.coral),
                ),
                TextSpan(text: word == 'Нона.' ? 'она' : word.substring(1)),
                if (word == 'Нона.')
                  const TextSpan(
                    text: '.',
                    style: TextStyle(color: NonaColor.coral),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DiagonalPanel extends CustomPainter {
  const _DiagonalPanel(this.mobile);

  final bool mobile;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    if (mobile) {
      path
        ..moveTo(w * 286 / 390, 0)
        ..lineTo(w * 436 / 390, 0)
        ..lineTo(w * 151 / 390, h)
        ..lineTo(w / 390, h);
    } else {
      path
        ..moveTo(w * 782 / 990, 0)
        ..lineTo(w * 1012 / 990, 0)
        ..lineTo(w * 820 / 990, h)
        ..lineTo(w * 590 / 990, h);
    }
    canvas.drawPath(path..close(), Paint()..color = const Color(0xFF1B405A));
  }

  @override
  bool shouldRepaint(_DiagonalPanel oldDelegate) =>
      oldDelegate.mobile != mobile;
}
