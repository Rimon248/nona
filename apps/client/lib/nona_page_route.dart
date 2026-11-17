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
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.12, 0),
        end: Offset.zero,
      ).animate(eased),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.7, end: 1).animate(eased),
        child: RepaintBoundary(child: child),
      ),
    );
  },
);
