import 'package:flutter/material.dart';

/// Reel Bot's look: violet to coral, rounded cards, quiet surfaces.
class Brand {
  static const violet = Color(0xFF6D4AFF);
  static const coral = Color(0xFFFF6B81);
  static const gradient = LinearGradient(colors: [violet, coral], begin: Alignment.topLeft, end: Alignment.bottomRight);

  static ThemeData theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: violet, brightness: b, tertiary: coral);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: b == Brightness.dark ? const Color(0xFF0F0D17) : const Color(0xFFF7F5FF),
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
                boxShadow: [BoxShadow(color: Brand.violet.withValues(alpha: 0.25 + 0.2 * t), blurRadius: 24 + 16 * t, offset: const Offset(0, 8))],
              ),
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: widget.size * (0.55 + 0.06 * t)),
            ),
          );
        },
      );
}
