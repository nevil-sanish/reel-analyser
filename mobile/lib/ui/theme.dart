import 'package:flutter/material.dart';

/// Reel Bot's look: the purple → pink → orange → yellow sunset of Reels, on near-black or near-white surfaces.
/// Colours only; Reel Bot keeps its own mark, never Instagram's logo.
class Brand {
  static const violet = Color(0xFF833AB4);
  static const magenta = Color(0xFFC13584);
  static const pink = Color(0xFFE1306C);
  static const orange = Color(0xFFF77737);
  static const yellow = Color(0xFFFCAF45);
  static const coral = orange;
  static const colors = [violet, magenta, pink, orange, yellow];
  static const gradient = LinearGradient(colors: colors, begin: Alignment.bottomLeft, end: Alignment.topRight);

  static ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: pink, brightness: b, primary: dark ? const Color(0xFFFF5C8A) : pink, tertiary: orange)
        .copyWith(surface: dark ? Colors.black : Colors.white);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? Colors.black : const Color(0xFFFAFAFA),
      appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0, backgroundColor: Colors.transparent),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: BorderSide.none),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
    );
  }
}

/// The app's mark: a gradient tile with a play glyph that breathes while [animate] is on.
class BrandMark extends StatefulWidget {
  final double size;
  final bool animate;
  const BrandMark({this.size = 96, this.animate = true, super.key});

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeInOut.transform((_c.value * 2 - 1).abs());
          return Transform.rotate(
            angle: (_c.value - 0.5) * 0.12,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                gradient: Brand.gradient,
                borderRadius: BorderRadius.circular(widget.size * 0.3),
                boxShadow: [BoxShadow(color: Brand.pink.withValues(alpha: 0.25 + 0.2 * t), blurRadius: 24 + 16 * t, offset: const Offset(0, 8))],
              ),
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: widget.size * (0.55 + 0.06 * t)),
            ),
          );
        },
      );
}
