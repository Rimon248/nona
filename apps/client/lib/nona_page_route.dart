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
      ? NonaMotion.duration(context, NonaMotion.quick)
      : Duration.zero,
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(opacity: animation, child: child),
);
