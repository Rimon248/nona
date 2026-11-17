import 'package:flutter/material.dart';

import 'nona_motion.dart';

Route<T> nonaPageRoute<T>(
  BuildContext context,
  Widget page, {
  bool animate = true,
}) => PageRouteBuilder<T>(
  transitionDuration: animate
      ? NonaMotion.duration(context, NonaMotion.page)
      : Duration.zero,
  reverseTransitionDuration: animate
      ? NonaMotion.duration(context, const Duration(milliseconds: 320))
      : Duration.zero,
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInOutCubic,
    );
    return ClipRect(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(eased),
        child: RepaintBoundary(child: child),
      ),
    );
  },
);
