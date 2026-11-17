import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nona_control_theme.dart';

abstract final class NonaMotion {
  static const quick = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 220);
  static const page = Duration(milliseconds: 420);
  static const startup = Duration(milliseconds: 520);

  static Duration duration(BuildContext context, Duration normal) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
}

/// A brief press and release on a cached circle, without repainting its content.
class NonaConnectionPress extends StatefulWidget {
  const NonaConnectionPress({
    super.key,
    required this.child,
    required this.enabled,
  });

  final Widget child;
  final bool enabled;

  @override
  State<NonaConnectionPress> createState() => _NonaConnectionPressState();
}

class _NonaConnectionPressState extends State<NonaConnectionPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 270),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.93,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 38,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.93,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 62,
    ),
  ]).animate(_press);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled && !MediaQuery.disableAnimationsOf(context)
        ? (_) => _press.forward(from: 0)
        : null,
    child: ScaleTransition(
      scale: _scale,
      child: RepaintBoundary(child: widget.child),
    ),
  );
}

/// The large VPN ring only animates its colors when the state changes.
class NonaConnectionHalo extends StatelessWidget {
  const NonaConnectionHalo({
    super.key,
    required this.size,
    required this.state,
    required this.unavailable,
  });

  final double size;
  final String state;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final color = unavailable
        ? NonaColor.coral
        : switch (state) {
            'connected' => const Color(0xFF3C9A72),
            'connecting' => NonaColor.muted,
            _ => NonaColor.coral,
          };
    final duration = NonaMotion.duration(context, NonaMotion.standard);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: duration,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: unavailable ? 3 : 2),
            ),
          ),
          AnimatedContainer(
            duration: duration,
            width: size - 25,
            height: size - 25,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.48)),
            ),
          ),
          NonaStatusDot(orbitSize: size),
        ],
      ),
    );
  }
}

class NonaStatusDot extends StatefulWidget {
  const NonaStatusDot({super.key, required this.orbitSize});

  final double orbitSize;

  @override
  State<NonaStatusDot> createState() => _NonaStatusDotState();
}

class _NonaStatusDotState extends State<NonaStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
    value: 0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _orbit.stop();
      _orbit.value = 0;
    } else if (!_orbit.isAnimating) {
      _orbit.repeat();
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _orbit,
    child: const RepaintBoundary(
      child: SizedBox(
        width: 16,
        height: 16,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NonaColor.coral,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
    builder: (context, child) {
      final angle = -math.pi / 3 + _orbit.value * 2 * math.pi;
      final radius = widget.orbitSize / 2 - 8;
      return Transform.translate(
        offset: Offset(radius * math.cos(angle), radius * math.sin(angle)),
        child: child,
      );
    },
  );
}

class NonaPingWave extends StatefulWidget {
  const NonaPingWave({super.key});

  @override
  State<NonaPingWave> createState() => _NonaPingWaveState();
}

class _NonaPingWaveState extends State<NonaPingWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Проверяем пинг',
    child: AnimatedBuilder(
      animation: _wave,
      builder: (context, _) => SizedBox(
        width: 24,
        height: 22,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (index) {
            final phase = _wave.value * math.pi * 2 - index * 0.9;
            final height = MediaQuery.disableAnimationsOf(context)
                ? 8.0
                : 7 + (math.sin(phase) + 1) * 6;
            return Container(
              width: 4,
              height: height,
              decoration: BoxDecoration(
                color: NonaColor.coral,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ),
    ),
  );
}
