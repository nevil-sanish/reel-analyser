import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Slowly drifting colour blobs behind everything; the glass surfaces sit on top of it.
class LiquidBackground extends StatefulWidget {
  const LiquidBackground({super.key});

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 30));

  // A stopped controller also stops asking for frames, which is the point of reducing effects.
  void _sync() => Brand.reduceEffects.value ? _c.stop() : _c.repeat();

  @override
  void initState() {
    super.initState();
    Brand.reduceEffects.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    Brand.reduceEffects.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _Blobs(_c.value, b), size: Size.infinite),
      ),
    );
  }
}

class _Blobs extends CustomPainter {
  final double t;
  final Brightness b;
  _Blobs(this.t, this.b);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = Brand.base(b));
    final a = b == Brightness.dark ? 0.35 : 0.28;
    final w = 2 * math.pi * t;
    // (colour, centre x, centre y, radius as a share of the long side, phase)
    final blobs = [
      (Brand.emerald, 0.15, 0.12, 0.55, 0.0),
      (Brand.mint, 0.9, 0.3, 0.5, 1.7),
      (Brand.lime, 0.2, 0.85, 0.45, 3.1),
      (Brand.green, 0.85, 0.95, 0.35, 4.4),
    ];
    for (final (color, x, y, r, phase) in blobs) {
      final c = Offset(s.width * (x + 0.12 * math.sin(w + phase)), s.height * (y + 0.08 * math.cos(w * 1.3 + phase)));
      final radius = s.longestSide * r;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [color.withValues(alpha: a), color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_Blobs old) => old.t != t || old.b != b;
}

/// Frosted glass: blurs what's behind it, with a tint, a hairline edge and a soft top highlight.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  const Glass({required this.child, this.radius = 28, this.padding = EdgeInsets.zero, super.key});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return ValueListenableBuilder(
      valueListenable: Brand.reduceEffects,
      builder: (_, reduced, _) {
        final surface = DecoratedBox(
          decoration: BoxDecoration(
            // Without the blur the tint is laid on the base colour, so text stays readable over the blobs.
            color: reduced ? Color.alphaBlend(Brand.glass(b), Brand.base(b)) : Brand.glass(b),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Brand.glassEdge(b)),
            gradient: reduced
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white.withValues(alpha: b == Brightness.dark ? 0.12 : 0.5), Colors.white.withValues(alpha: 0.02)],
                  ),
          ),
          child: Padding(padding: padding, child: child),
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: reduced ? surface : BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: surface),
        );
      },
    );
  }
}

/// A Scaffold on the liquid background. Tab pages inside the home pass `background: false`: the home draws it once.
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

/// The floating frosted tab bar at the bottom of the home screen.
class GlassTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> tabs;
  const GlassTabBar({required this.index, required this.onTap, required this.tabs, super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(40, 0, 40, 12),
      child: Glass(
        radius: 32,
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i == index) return;
                    HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: i == index ? Brand.gradient : null,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(i == index ? tabs[i].$2 : tabs[i].$1, color: i == index ? Colors.white : c.onSurfaceVariant, size: 22),
                      const SizedBox(height: 2),
                      Text(tabs[i].$3,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: i == index ? Colors.white : c.onSurfaceVariant)),
                    ]),
                  ),
                ),
              ),
          ],
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
        HapticFeedback.lightImpact();
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

/// "Liquid" page transition: the new page swells up from 92% with a fade while the old one sinks back.
class LiquidPageTransitionsBuilder extends PageTransitionsBuilder {
  const LiquidPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final inCurve = CurvedAnimation(parent: animation, curve: Curves.easeOutQuint, reverseCurve: Curves.easeInCubic);
    final out = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: inCurve,
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(inCurve),
        child: ScaleTransition(scale: Tween(begin: 1.0, end: 0.96).animate(out), child: child),
      ),
    );
  }
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
