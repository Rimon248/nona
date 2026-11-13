import 'dart:async';

import 'package:flutter/material.dart';

import 'nona_control_theme.dart';

class DelayedProgressIndicator extends StatefulWidget {
  const DelayedProgressIndicator({
    super.key,
    required this.message,
    this.compact = false,
    this.delay = const Duration(milliseconds: 250),
  });

  final String message;
  final bool compact;
  final Duration delay;

  @override
  State<DelayedProgressIndicator> createState() =>
      _DelayedProgressIndicatorState();
}

class _DelayedProgressIndicatorState extends State<DelayedProgressIndicator> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 12.0 : 18.0;
    return SizedBox(
      height: widget.compact ? 18 : 24,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 100),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: widget.compact ? 1.8 : 2,
                color: NonaColor.coral,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.message,
              style: TextStyle(
                color: NonaColor.muted,
                fontSize: widget.compact ? 11 : 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
