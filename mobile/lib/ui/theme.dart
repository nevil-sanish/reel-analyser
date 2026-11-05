import 'package:flutter/material.dart';

import 'liquid.dart';

/// Reel Bot's look (v0.8.1): greens only, from deep emerald to fresh lime, on white by default or near-black.
class Brand {
  static const forest = Color(0xFF047857);
  static const emerald = Color(0xFF10B981);
  static const green = Color(0xFF22C55E);
  static const mint = Color(0xFF6EE7B7);
  static const lime = Color(0xFFA3E635);
  static const colors = [forest, emerald, green, mint, lime];
  static const gradient = LinearGradient(colors: [forest, emerald, green, lime], begin: Alignment.bottomLeft, end: Alignment.topRight);

  /// Light by default; Settings and the sun/moon button switch it. Saved, so it sticks across launches.
  static final mode = ValueNotifier(ThemeMode.light);

  /// The glass tint over the liquid background: clear in dark mode, milky in light.
  static Color glass(Brightness b) => b == Brightness.dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.7);
  static Color glassEdge(Brightness b) =>
      b == Brightness.dark ? Colors.white.withValues(alpha: 0.14) : emerald.withValues(alpha: 0.18);
  static Color base(Brightness b) => b == Brightness.dark ? const Color(0xFF050B08) : const Color(0xFFF7FBF8);

  static ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: emerald, brightness: b, primary: dark ? mint : forest, tertiary: lime)
        .copyWith(surface: base(b));
    final glassShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: glassEdge(b)));
    final base0 = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
    // iOS-like type: heavier titles, tighter tracking.
    final text = base0.textTheme.copyWith(
      displayLarge: base0.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5),
      headlineSmall: base0.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: base0.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: base0.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    );
    return base0.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: base(b),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: LiquidPageTransitionsBuilder(),
        TargetPlatform.iOS: LiquidPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w800, letterSpacing: -0.6),
      ),
      cardTheme: CardThemeData(elevation: 0, margin: EdgeInsets.zero, color: glass(b), shape: glassShape),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(glass(b)),
        side: WidgetStatePropertyAll(BorderSide(color: glassEdge(b))),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glass(b),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: glassEdge(b))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: glassEdge(b))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: scheme.primary)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: glass(b),
        shape: StadiumBorder(side: BorderSide(color: glassEdge(b))),
        side: BorderSide(color: glassEdge(b)),
      ),
      dialogTheme: DialogThemeData(backgroundColor: base(b).withValues(alpha: 0.92), shape: glassShape),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: base(b).withValues(alpha: 0.95)),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: StadiumBorder()),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: const StadiumBorder())),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: const StadiumBorder())),
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
                boxShadow: [BoxShadow(color: Brand.emerald.withValues(alpha: 0.25 + 0.2 * t), blurRadius: 24 + 16 * t, offset: const Offset(0, 8))],
              ),
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: widget.size * (0.55 + 0.06 * t)),
            ),
          );
        },
      );
}
