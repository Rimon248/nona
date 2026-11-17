import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nona_control_theme.dart';

abstract final class NonaMotion {
  static const quick = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 220);
  static const page = Duration(milliseconds: 160);

  static Duration duration(BuildContext context, Duration normal) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
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
        ],
      ),
    );
  }
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
