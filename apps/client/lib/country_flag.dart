import 'package:flutter/material.dart';

/// Draws flags without relying on the host system's emoji font. Windows can
/// render regional-indicator emoji as two letters instead of a flag.
class CountryFlag extends StatelessWidget {
  const CountryFlag({super.key, required this.country, this.size = 22});

  final String? country;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (country != 'Нидерланды' && country != 'Швеция') {
      return Icon(
        Icons.public,
        size: size,
        color: Theme.of(context).colorScheme.onSurface,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .08),
      child: CustomPaint(
        size: Size(size, size * .67),
        painter: _FlagPainter(country!),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  const _FlagPainter(this.country);

  final String country;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    if (country == 'Нидерланды') {
      paint.color = const Color(0xFFAE1C28);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height / 3), paint);
      paint.color = Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(0, size.height / 3, size.width, size.height / 3),
        paint,
      );
      paint.color = const Color(0xFF21468B);
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * 2 / 3, size.width, size.height / 3),
        paint,
      );
    } else {
      paint.color = const Color(0xFF006AA7);
      canvas.drawRect(Offset.zero & size, paint);
      paint.color = const Color(0xFFFECC00);
      canvas.drawRect(
        Rect.fromLTWH(size.width * 5 / 16, 0, size.width * 2 / 16, size.height),
        paint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          size.height * 4 / 10,
          size.width,
          size.height * 2 / 10,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) =>
      oldDelegate.country != country;
}
