import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
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

  /// The glass tint over the liquid background: clear in dark mode, milky in light.
  static Color glass(Brightness b) => b == Brightness.dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.55);
  static Color glassEdge(Brightness b) => b == Brightness.dark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.8);
  static Color base(Brightness b) => b == Brightness.dark ? const Color(0xFF07060B) : const Color(0xFFF2F1F6);

  static ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: pink, brightness: b, primary: dark ? const Color(0xFFFF5C8A) : pink, tertiary: orange)
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
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
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
                boxShadow: [BoxShadow(color: Brand.pink.withValues(alpha: 0.25 + 0.2 * t), blurRadius: 24 + 16 * t, offset: const Offset(0, 8))],
              ),
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: widget.size * (0.55 + 0.06 * t)),
            ),
          );
        },
      );
}
