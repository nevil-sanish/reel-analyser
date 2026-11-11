import 'package:flutter/material.dart';

import 'theme.dart';

/// A small badge for where a note came from: Instagram, YouTube, or a photo shared from the phone. Drawn here so no icon
/// package or image asset is needed.
class SourceIcon extends StatelessWidget {
  /// The note's `app`: `instagram`, `youtube` or `photo`.
  final String app;
  final double size;
  const SourceIcon(this.app, {this.size = 28, super.key});

  static String label(String app) => switch (app) {
        'youtube' => 'YouTube',
        'photo' => 'Shared photo',
        _ => 'Instagram',
      };

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(size * 0.28);
    final Widget badge = switch (app) {
      'youtube' => DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xFFFF0000), borderRadius: r),
          child: Center(child: Icon(Icons.play_arrow_rounded, size: size * 0.72, color: Colors.white)),
        ),
      'photo' => DecoratedBox(
          decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: r),
          child: Center(child: Icon(Icons.photo_rounded, size: size * 0.6, color: Brand.onGold)),
        ),
      _ => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: const LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF), Color(0xFF4F5BD5)],
            ),
          ),
          child: CustomPaint(painter: _CameraGlyph()),
        ),
    };
    return Semantics(label: label(app), child: SizedBox.square(dimension: size, child: badge));
  }
}

/// The rounded square, lens and dot of a camera, in white.
class _CameraGlyph extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.2, w * 0.2, w * 0.6, w * 0.6), Radius.circular(w * 0.17)), p);
    c.drawCircle(Offset(w * 0.5, w * 0.5), w * 0.14, p);
    c.drawCircle(Offset(w * 0.665, w * 0.335), w * 0.035, p..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_CameraGlyph old) => false;
}
