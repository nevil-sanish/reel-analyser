import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'liquid.dart';

/// Reel Analyser's look (v1.1): Hellenic. Warm marble white and gold, serif titles, hairline gold edges, a Greek key
/// for ornament. Light by default, or deep charcoal with gold.
class Brand {
  /// The gold: [gold] for fills and lines, [goldDeep] for text and icons on marble (it reads at 4.5:1 there).
  static const gold = Color(0xFFC9A227);
  static const goldDeep = Color(0xFF8A6A12);
  static const goldLight = Color(0xFFE9D48A);
  static const goldPale = Color(0xFFF4EACB);
  static const bronze = Color(0xFF9A7414);

  /// Text and icons on gold, and text on marble.
  static const ink = Color(0xFF1C1A14);
  static const ivory = Color(0xFFF6F1E4);
  static const marble = Color(0xFFFBF9F4);
  static const night = Color(0xFF0F0E0B);
  static const nightSurface = Color(0xFF191712);

  /// What sits on gold fills: dark ink, never white.
  static const onGold = ink;
  static const gradient = LinearGradient(colors: [bronze, gold, goldLight], begin: Alignment.bottomLeft, end: Alignment.topRight);
  static const colors = [bronze, gold, goldLight, goldPale];

  /// Light by default; Settings and the sun/moon button switch it. Saved, so it sticks across launches.
  static final mode = ValueNotifier(ThemeMode.light);

  /// Settings → Reduce motion: no entrance animations, glow or drifting; the look stays.
  static final reduceEffects = ValueNotifier(false);

  static Color base(Brightness b) => b == Brightness.dark ? night : marble;
  static Color surface(Brightness b) => b == Brightness.dark ? nightSurface : Colors.white;

  /// The tint of a card: nearly opaque, so text stays sharp and nothing needs a blur (which is slow on many phones).
  static Color glass(Brightness b) => b == Brightness.dark ? nightSurface.withValues(alpha: 0.94) : Colors.white.withValues(alpha: 0.9);
  static Color glassEdge(Brightness b) => gold.withValues(alpha: b == Brightness.dark ? 0.32 : 0.38);

  static TextStyle serif(TextStyle? base, {double? size, double weight = 600, double? spacing, double? height}) =>
      (base ?? const TextStyle()).copyWith(
        fontFamily: 'Cormorant',
        fontVariations: [FontVariation('wght', weight)],
        // Lining figures: the serif's old-style digits make a 1 look like a small capital I.
        fontFeatures: const [FontFeature.liningFigures()],
        fontSize: size,
        letterSpacing: spacing,
        height: height,
      );

  static ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: gold, brightness: b).copyWith(
      primary: dark ? gold : goldDeep,
      onPrimary: dark ? ink : Colors.white,
      primaryContainer: dark ? const Color(0xFF3A2F0F) : goldPale,
      onPrimaryContainer: dark ? goldLight : const Color(0xFF3B2D06),
      secondary: gold,
      onSecondary: ink,
      secondaryContainer: dark ? const Color(0xFF2A2412) : goldPale,
      onSecondaryContainer: dark ? goldLight : const Color(0xFF3B2D06),
      tertiary: bronze,
      surface: base(b),
      onSurface: dark ? ivory : ink,
      onSurfaceVariant: dark ? const Color(0xFFB9B09A) : const Color(0xFF6B6455),
      surfaceContainerHighest: dark ? const Color(0xFF241F14) : const Color(0xFFF1EBDA),
      outline: gold.withValues(alpha: 0.6),
      outlineVariant: gold.withValues(alpha: 0.28),
      error: dark ? const Color(0xFFE58B7B) : const Color(0xFF9E3B2D),
    );
    final edge = glassEdge(b);
    final cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: edge));
    final base0 = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b, fontFamily: 'Lato');
    final body = base0.textTheme;
    // Titles in the serif (it runs small, so the sizes are a step up), everything else in the clean sans.
    final text = body.copyWith(
      displayLarge: serif(body.displayLarge, size: 60, weight: 600, spacing: -1),
      displayMedium: serif(body.displayMedium, size: 48, weight: 600, spacing: -0.5),
      displaySmall: serif(body.displaySmall, size: 42, weight: 600, spacing: -0.3),
      headlineLarge: serif(body.headlineLarge, size: 38, weight: 600),
      headlineMedium: serif(body.headlineMedium, size: 34, weight: 600),
      headlineSmall: serif(body.headlineSmall, size: 30, weight: 600),
      titleLarge: serif(body.titleLarge, size: 27, weight: 600),
      titleMedium: serif(body.titleMedium, size: 21, weight: 600),
      titleSmall: body.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3),
    );
    return base0.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: base(b),
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: LiquidPageTransitionsBuilder(),
        TargetPlatform.iOS: LiquidPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: serif(text.headlineSmall, size: 29, weight: 600).copyWith(color: scheme.onSurface),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        ),
      ),
      iconTheme: IconThemeData(color: dark ? goldLight : goldDeep),
      dividerTheme: DividerThemeData(color: gold.withValues(alpha: 0.3), thickness: 0.8, space: 24),
      cardTheme: CardThemeData(elevation: 0, margin: EdgeInsets.zero, color: glass(b), shape: cardShape, shadowColor: Colors.black),
      listTileTheme: ListTileThemeData(iconColor: dark ? goldLight : goldDeep, minVerticalPadding: 10),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(surface(b)),
        side: WidgetStatePropertyAll(BorderSide(color: edge)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? nightSurface : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: edge)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: edge)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: gold, width: 1.6)),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? nightSurface : Colors.white,
        selectedColor: scheme.primaryContainer,
        shape: StadiumBorder(side: BorderSide(color: edge)),
        side: BorderSide(color: edge),
        labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        checkmarkColor: scheme.primary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? nightSurface : marble,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: edge)),
        titleTextStyle: serif(text.titleLarge, size: 26, weight: 600).copyWith(color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? nightSurface : marble,
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(28)), side: BorderSide(color: edge)),
        showDragHandle: true,
        dragHandleColor: gold.withValues(alpha: 0.6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? goldPale : ink,
        contentTextStyle: TextStyle(color: dark ? ink : ivory, fontWeight: FontWeight.w600),
        actionTextColor: dark ? bronze : goldLight,
        shape: const StadiumBorder(),
      ),
      bannerTheme: MaterialBannerThemeData(backgroundColor: dark ? nightSurface : goldPale, dividerColor: Colors.transparent),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: ink,
          disabledBackgroundColor: gold.withValues(alpha: 0.3),
          minimumSize: const Size(64, 50),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: gold.withValues(alpha: 0.7)),
          minimumSize: const Size(64, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: scheme.primary, textStyle: const TextStyle(fontWeight: FontWeight.w700))),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? ink : (dark ? const Color(0xFF8A8372) : const Color(0xFFB9B09A))),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? gold : (dark ? const Color(0xFF2A261C) : const Color(0xFFEDE6D2))),
        trackOutlineColor: WidgetStatePropertyAll(gold.withValues(alpha: 0.5)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? gold : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(ink),
        side: BorderSide(color: gold.withValues(alpha: 0.8), width: 1.4),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (dark ? const Color(0xFF3A2F0F) : goldPale) : Colors.transparent),
          foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
          side: WidgetStatePropertyAll(BorderSide(color: gold.withValues(alpha: 0.6))),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: gold, linearTrackColor: Color(0x33C9A227)),
      timePickerTheme: TimePickerThemeData(backgroundColor: dark ? nightSurface : marble, dialHandColor: gold, hourMinuteColor: scheme.primaryContainer),
    );
  }
}

/// The app's mark, the same drawing as the launcher icon (tool/make_icon.py): a charcoal disc, a thin gold ring, a ring of
/// Greek key and a play mark. The key ring turns very slowly; it stops when motion is reduced.
class BrandMark extends StatefulWidget {
  final double size;
  final bool animate;
  const BrandMark({this.size = 96, this.animate = true, super.key});

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 90));

  @override
  void initState() {
    super.initState();
    if (widget.animate && !Brand.reduceEffects.value) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(painter: _EmblemPainter(_c.value))),
        ),
      );
}

class _EmblemPainter extends CustomPainter {
  final double turn;
  _EmblemPainter(this.turn);

  // The same numbers as tool/make_icon.py, in a 108 x 108 square.
  static const _c = 54.0, _ring = 31.0, _in = 21.5, _out = 26.5, _inner = 19.0, _n = 24;
  static const _key = [(0.0, 1.0), (0.0, 0.0), (0.72, 0.0), (0.72, 0.66), (0.32, 0.66), (0.32, 0.33), (0.5, 0.33)];

  static Offset _pt(double theta, double r) => Offset(_c + r * math.cos(theta), _c + r * math.sin(theta));

  static Path _meander(double spin) {
    final path = Path();
    const w = 2 * math.pi / _n;
    for (var k = 0; k < _n; k++) {
      final a0 = -math.pi / 2 + k * w + spin;
      (double, double)? prev;
      for (final (u, v) in _key) {
        final r = _in + (1 - v) * (_out - _in);
        if (prev == null) {
          final o = _pt(a0 + u * w, r);
          path.moveTo(o.dx, o.dy);
        } else if ((prev.$2 - v).abs() < 1e-9) {
          final steps = math.max(2, ((u - prev.$1).abs() * 6).floor());
          for (var s = 1; s <= steps; s++) {
            final o = _pt(a0 + (prev.$1 + (u - prev.$1) * s / steps) * w, r);
            path.lineTo(o.dx, o.dy);
          }
        } else {
          final o = _pt(a0 + u * w, r);
          path.lineTo(o.dx, o.dy);
        }
        prev = (u, v);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108);
    const box = Rect.fromLTWH(0, 0, 108, 108);
    final disc = Path()..addOval(const Rect.fromLTWH(0, 0, 108, 108));
    canvas.clipPath(disc);
    canvas.drawRect(
      box,
      Paint()..shader = const RadialGradient(center: Alignment(0, -0.11), radius: 0.67, colors: [Color(0xFF1F1C14), Color(0xFF0C0B08)]).createShader(box),
    );
    final gold = const LinearGradient(begin: Alignment(-0.67, 0.67), end: Alignment(0.67, -0.67), colors: [Color(0xFF8A6410), Brand.gold, Color(0xFFEFD98F)]).createShader(box);
    Paint stroke(double w, [double a = 1]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..shader = gold
      ..color = Colors.white.withValues(alpha: a);
    canvas.drawCircle(const Offset(_c, _c), _ring, stroke(0.9));
    canvas.drawCircle(const Offset(_c, _c), _inner, stroke(0.55, 0.6));
    canvas.drawPath(_meander(turn * 2 * math.pi), stroke(1.1)..strokeJoin = StrokeJoin.miter);
    final play = Path()
      ..moveTo(_c - 5.4, _c - 9.2)
      ..lineTo(_c - 5.4, _c + 9.2)
      ..lineTo(_c + 10.2, _c)
      ..close();
    canvas.drawPath(play, Paint()..shader = gold);
    canvas.drawPath(play, stroke(2.4)..strokeJoin = StrokeJoin.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmblemPainter old) => old.turn != turn;
}
