
import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

/// Warm marble behind everything: a still base, two soft pools of gold light and a few faint veins. It never animates,
/// so it costs nothing after the first frame.
class LiquidBackground extends StatelessWidget {
  const LiquidBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return RepaintBoundary(child: CustomPaint(painter: _Marble(b), size: Size.infinite, isComplex: true, willChange: false));
  }
}

class _Marble extends CustomPainter {
  final Brightness b;
  _Marble(this.b);

  @override
  void paint(Canvas canvas, Size s) {
    final dark = b == Brightness.dark;
    canvas.drawRect(Offset.zero & s, Paint()..color = Brand.base(b));
    void pool(Offset c, double r, double a) => canvas.drawCircle(
        c, r, Paint()..shader = RadialGradient(colors: [Brand.gold.withValues(alpha: a), Brand.gold.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)));
    pool(Offset(s.width * 0.95, s.height * 0.04), s.longestSide * 0.5, dark ? 0.12 : 0.16);
    pool(Offset(s.width * 0.02, s.height * 0.96), s.longestSide * 0.4, dark ? 0.07 : 0.1);
    final vein = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (dark ? Brand.goldLight : Brand.goldDeep).withValues(alpha: dark ? 0.05 : 0.055);
    final w = s.width, h = s.height;
    canvas.drawPath(Path()..moveTo(-10, h * 0.18)..cubicTo(w * 0.3, h * 0.1, w * 0.55, h * 0.3, w + 10, h * 0.2), vein);
    canvas.drawPath(Path()..moveTo(w * 0.1, h + 10)..cubicTo(w * 0.2, h * 0.7, w * 0.6, h * 0.62, w + 10, h * 0.5), vein);
    canvas.drawPath(Path()..moveTo(-10, h * 0.62)..cubicTo(w * 0.25, h * 0.5, w * 0.35, h * 0.8, w * 0.7, h * 0.96), vein);
  }

  @override
  bool shouldRepaint(_Marble old) => old.b != b;
}

/// A card: marble white (or charcoal) with a hairline gold edge and a soft shadow. No blur, so it is cheap to draw and scroll.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Fully opaque, for bars that content scrolls under.
  final bool solid;
  const Glass({required this.child, this.radius = 24, this.padding = EdgeInsets.zero, this.solid = false, super.key});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        color: solid ? Brand.surface(b) : Brand.glass(b),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Brand.glassEdge(b)),
        boxShadow: [BoxShadow(color: (b == Brightness.dark ? Colors.black : Brand.goldDeep).withValues(alpha: b == Brightness.dark ? 0.35 : 0.1), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius - 1), child: Padding(padding: padding, child: child)),
    );
  }
}

/// A Scaffold on the marble background. Tab pages inside the home pass `background: false`: the home draws it once.
class LiquidScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final bool background;
  const LiquidScaffold({this.appBar, this.body, this.floatingActionButton, this.background = true, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: background ? Brand.base(Theme.of(context).brightness) : Colors.transparent,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        body: background ? Stack(children: [const Positioned.fill(child: LiquidBackground()), ?body]) : body,
      );
}

/// The floating tab bar at the bottom of the home screen: a gold line slides under the chosen tab.
class GlassTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> tabs;
  const GlassTabBar({required this.index, required this.onTap, required this.tabs, super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = dark ? Brand.gold : Brand.goldDeep;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      child: Glass(
        radius: 30,
        solid: true,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / tabs.length;
            return Stack(children: [
              AnimatedPositioned(
                duration: Brand.reduceEffects.value ? Duration.zero : const Duration(milliseconds: 380),
                curve: Curves.easeOutBack,
                left: index * w + w / 2 - 15,
                top: 0,
                child: Container(width: 30, height: 3, decoration: const BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)))),
              ),
              Row(children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: Pressable(
                      scale: 0.92,
                      haptic: false,
                      onTap: () {
                        if (i == index) return;
                        Haptics.select();
                        onTap(i);
                      },
                      child: SizedBox(
                        height: 64,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedScale(
                            scale: i == index ? 1.12 : 1,
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutBack,
                            child: Icon(i == index ? tabs[i].$2 : tabs[i].$1, color: i == index ? on : c.onSurfaceVariant, size: 24),
                          ),
                          const SizedBox(height: 3),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            style: TextStyle(fontSize: 11, letterSpacing: 0.5, fontWeight: i == index ? FontWeight.w700 : FontWeight.w500, color: i == index ? on : c.onSurfaceVariant),
                            child: Text(tabs[i].$3),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}

/// Sun / moon button that flips between the light (default) and dark themes, with a little spin.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Light mode' : 'Dark mode',
      onPressed: () {
        Haptics.light();
        Brand.mode.value = dark ? ThemeMode.light : ThemeMode.dark;
      },
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, a) => RotationTransition(turns: Tween(begin: 0.5, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: child)),
        child: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, key: ValueKey(dark)),
      ),
    );
  }
}

/// Page transition: the new page rises a little and fades in, the old one dims. Only a fade when motion is reduced.
class LiquidPageTransitionsBuilder extends PageTransitionsBuilder {
  const LiquidPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final inCurve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final out = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    final fade = FadeTransition(opacity: Tween(begin: 1.0, end: 0.88).animate(out), child: FadeTransition(opacity: inCurve, child: child));
    if (Brand.reduceEffects.value) return fade;
    return SlideTransition(
      position: Tween(begin: const Offset(0, 0.035), end: Offset.zero).animate(inCurve),
      child: ScaleTransition(scale: Tween(begin: 0.985, end: 1.0).animate(inCurve), child: fade),
    );
  }
}


/// A Greek key (meander) border in gold: the app's one ornament. Use it as a divider under a title or between sections.
class MeanderDivider extends StatelessWidget {
  final double height;
  final double opacity;
  const MeanderDivider({this.height = 9, this.opacity = 0.7, super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _Meander((dark ? Brand.gold : Brand.bronze).withValues(alpha: opacity)),
      ),
    );
  }
}

class _Meander extends CustomPainter {
  final Color color;
  _Meander(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final h = s.height;
    // Whole keys only, stretched a hair so the pattern ends exactly at the right edge.
    final n = (s.width / (h * 1.6)).floor().clamp(1, 1000);
    final u = s.width / n;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.miter
      ..color = color;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = i * u;
      path
        ..moveTo(x, h)
        ..lineTo(x, 0)
        ..lineTo(x + u * 0.72, 0)
        ..lineTo(x + u * 0.72, h * 0.66)
        ..lineTo(x + u * 0.32, h * 0.66)
        ..lineTo(x + u * 0.32, h * 0.33)
        ..lineTo(x + u * 0.5, h * 0.33);
    }
    canvas.drawPath(path, p);
    canvas.drawLine(Offset(0, h), Offset(s.width, h), p..strokeWidth = 0.8);
  }

  @override
  bool shouldRepaint(_Meander old) => old.color != color;
}

/// Tabs that all stay alive (like IndexedStack) and cross-fade. The fade sits outside TickerMode: muting a hidden
/// tab's tickers must not also freeze its own fade-out, or it stays half-visible over the others (the v0.8.1 bug).
class FadingTabs extends StatelessWidget {
  final int index;
  final List<Widget> children;
  const FadingTabs({required this.index, required this.children, super.key});

  @override
  Widget build(BuildContext context) => Stack(children: [
        for (final (i, page) in children.indexed)
          AnimatedOpacity(
            opacity: i == index ? 1 : 0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: IgnorePointer(
              ignoring: i != index,
              child: ExcludeSemantics(excluding: i != index, child: TickerMode(enabled: i == index, child: page)),
            ),
          ),
      ]);
}
