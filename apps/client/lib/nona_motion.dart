import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'nona_control_theme.dart';

abstract final class NonaMotion {
  static const quick = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 220);
  static const page = Duration(milliseconds: 420);
  static const startup = Duration(milliseconds: 520);

  static Duration duration(BuildContext context, Duration normal) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
}

class NonaCardSortItem extends StatefulWidget {
  const NonaCardSortItem({
    super.key,
    required this.step,
    required this.enabled,
    required this.child,
  });

  final int step;
  final bool enabled;
  final Widget child;

  @override
  State<NonaCardSortItem> createState() => _NonaCardSortItemState();
}

class _NonaCardSortItemState extends State<NonaCardSortItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 430),
    value: widget.enabled ? 0 : 1,
  );
  Timer? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) {
      _start?.cancel();
      _entry.value = 1;
    } else if (_entry.value == 0 && _start == null) {
      _start = Timer(Duration(milliseconds: 90 + widget.step * 115), () {
        if (mounted) _entry.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant NonaCardSortItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _start?.cancel();
      _entry.value = 1;
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = CurvedAnimation(
      parent: _entry,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(progress),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
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
    this.loading = false,
  });

  final double size;
  final String state;
  final bool unavailable;
  final bool loading;

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
        clipBehavior: Clip.none,
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
          NonaStatusDot(orbitSize: size, active: loading),
        ],
      ),
    );
  }
}

class NonaStatusDot extends StatefulWidget {
  const NonaStatusDot({
    super.key,
    required this.orbitSize,
    required this.active,
  });

  final double orbitSize;
  final bool active;

  @override
  State<NonaStatusDot> createState() => _NonaStatusDotState();
}

class _NonaStatusDotState extends State<NonaStatusDot>
    with SingleTickerProviderStateMixin {
  static const _fullSpeed = 1.8; // Revolutions per second.
  static const _acceleration = 2.2;
  static const _braking = 1.3;

  final ValueNotifier<double> _phase = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_advance);
  Duration _lastTick = Duration.zero;
  double _turns = 0;
  double _speed = 0;
  double? _stopAt;
  double _stopFrom = 0;
  double _stopSpeed = 0;
  double _stopElapsed = 0;
  double _stopDuration = 0;

  @override
  void didUpdateWidget(covariant NonaStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _ticker.stop();
      _turns = 0;
      _speed = 0;
      _stopAt = null;
      _phase.value = 0;
    } else if (widget.active) {
      _stopAt = null;
      if (!_ticker.isActive) {
        _lastTick = Duration.zero;
        _ticker.start();
      }
    } else {
      if (!_ticker.isActive || _stopAt != null) return;
      final brakingDistance = _speed * _speed / (2 * _braking);
      _stopFrom = _turns;
      _stopSpeed = _speed;
      _stopElapsed = 0;
      _stopAt = (_turns + math.max(brakingDistance, 0.03)).ceilToDouble();
      final distance = _stopAt! - _stopFrom;
      _stopDuration = (2 * distance / math.max(_speed, 0.6)).clamp(
        1.2,
        2.6,
      );
    }
  }

  void _advance(Duration elapsed) {
    final delta = ((elapsed - _lastTick).inMicroseconds / 1000000).clamp(
      0.0,
      0.05,
    );
    _lastTick = elapsed;
    if (_stopAt != null) {
      _stopElapsed = math.min(_stopDuration, _stopElapsed + delta);
      final t = _stopElapsed / _stopDuration;
      if (t >= 1) {
        _ticker.stop();
        _turns = 0;
        _speed = 0;
        _stopAt = null;
        _phase.value = 0;
        return;
      }
      final distance = _stopAt! - _stopFrom;
      final startingSlope = _stopSpeed * _stopDuration / distance;
      // Cubic Hermite curve keeps the current velocity and reaches zero at home.
      final position = startingSlope * (t - 2 * t * t + t * t * t) +
          3 * t * t - 2 * t * t * t;
      final slope = startingSlope * (1 - 4 * t + 3 * t * t) +
          6 * t - 6 * t * t;
      _turns = _stopFrom + distance * position;
      _speed = math.max(0, distance * slope / _stopDuration);
      _phase.value = _turns % 1;
      return;
    }
    final oldSpeed = _speed;
    _speed = math.min(_fullSpeed, _speed + _acceleration * delta);
    _turns += (oldSpeed + _speed) * delta / 2;
    if (_turns >= 1) _turns %= 1;
    _phase.value = _turns % 1;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _phase,
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
      final angle = -math.pi / 3 + _phase.value * 2 * math.pi;
      final radius = widget.orbitSize / 2 + 8;
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
