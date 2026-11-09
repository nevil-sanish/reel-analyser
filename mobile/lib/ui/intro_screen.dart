import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

/// First run: a spinning gradient ring around the mark, three short pages, then "slide to unlock" bursts the
/// gradient across the screen and opens the app.
class IntroScreen extends StatefulWidget {
  final VoidCallback onDone;
  const IntroScreen({required this.onDone, super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with TickerProviderStateMixin {
  final _pages = PageController();
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  var _page = 0;

  static const _slides = [
    (Icons.ios_share_rounded, 'Share a reel.\nGet the point.', 'Tap Share → Reel Analyser on any reel or short. You get a short summary and the key takeaways.'),
    (Icons.insights_rounded, 'Know your scroll', 'See how many reels you watch each day and for how long. Counted, never recorded.'),
    (Icons.lock_rounded, 'Only on your phone', 'No account, no server. Your notes stay here; a reel you share goes only to the AI you choose.'),
  ];

  @override
  void dispose() {
    _spin.dispose();
    _enter.dispose();
    _burst.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    Haptics.heavy();
    await _burst.forward();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: Brand.base(Theme.of(context).brightness),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(onPressed: _unlock, child: Text('Skip', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                ),
                const SizedBox(height: 8),
                // The mark drops in, then sits inside a slowly turning gradient ring.
                ScaleTransition(
                  scale: CurvedAnimation(parent: _enter, curve: Curves.elasticOut),
                  child: SizedBox.square(
                    dimension: 150,
                    child: Stack(alignment: Alignment.center, children: [
                      AnimatedBuilder(
                        animation: _spin,
                        builder: (_, child) => Transform.rotate(angle: _spin.value * 2 * math.pi, child: child),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(colors: [...Brand.colors, Brand.bronze]),
                          ),
                        ),
                      ),
                      Container(width: 138, height: 138, decoration: BoxDecoration(color: Brand.base(Theme.of(context).brightness), shape: BoxShape.circle)),
                      const BrandMark(size: 96),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: CurvedAnimation(parent: _enter, curve: const Interval(0.4, 1)),
                  child: ShaderMask(
                    shaderCallback: (r) => Brand.gradient.createShader(r),
                    child: Text('Reel Analyser', style: Brand.serif(const TextStyle(color: Colors.white), size: 46, weight: 600, spacing: 0.5)),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => _Slide(_slides[i], active: i == _page),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _page ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: i == _page ? Brand.gradient : null,
                          color: i == _page ? null : Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: last
                        ? _SlideToUnlock(onUnlock: _unlock)
                        : SizedBox(
                            key: const ValueKey('next'),
                            width: double.infinity,
                            height: 60,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(context).colorScheme.onSurface,
                                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              ),
                              onPressed: () {
                                Haptics.select();
                                _pages.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
                              },
                              child: const Text('Next', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // Unlock: the gradient grows from the bottom of the screen until it covers everything.
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _burst,
              builder: (_, _) => _burst.value == 0
                  ? const SizedBox()
                  : CustomPaint(size: size, painter: _Burst(Curves.easeInCubic.transform(_burst.value))),
            ),
          ),
        ],
      ),
    );
  }
}

class _Burst extends CustomPainter {
  final double t;
  _Burst(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final center = Offset(s.width / 2, s.height - 62);
    final r = t * s.longestSide * 1.3;
    canvas.drawCircle(center, r, Paint()..shader = Brand.gradient.createShader(Rect.fromCircle(center: center, radius: math.max(r, 1))));
  }

  @override
  bool shouldRepaint(_Burst old) => old.t != t;
}

/// A pill track with a gradient thumb; drag it most of the way to unlock, or it springs back.
class _SlideToUnlock extends StatefulWidget {
  final VoidCallback onUnlock;
  const _SlideToUnlock({required this.onUnlock});

  @override
  State<_SlideToUnlock> createState() => _SlideToUnlockState();
}

class _SlideToUnlockState extends State<_SlideToUnlock> with SingleTickerProviderStateMixin {
  static const _h = 60.0;
  double _x = 0;
  bool _done = false;
  late final _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final max = c.maxWidth - _h;
        return Container(
          height: _h,
          decoration: BoxDecoration(
            color: Brand.glass(Theme.of(context).brightness),
            border: Border.all(color: Brand.glassEdge(Theme.of(context).brightness)),
            borderRadius: BorderRadius.circular(_h / 2),
          ),
          child: Stack(alignment: Alignment.centerLeft, children: [
            // The label shimmers left to right, hinting which way to slide.
            Center(
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (_, child) => ShaderMask(
                  shaderCallback: (r) => LinearGradient(
                    colors: [for (final a in [0.3, 1.0, 0.3]) Theme.of(context).colorScheme.onSurface.withValues(alpha: a)],
                    stops: [(_shimmer.value - 0.2).clamp(0, 1), _shimmer.value, (_shimmer.value + 0.2).clamp(0, 1)],
                  ).createShader(r),
                  child: child,
                ),
                child: Opacity(
                  opacity: (1 - _x / max).clamp(0, 1),
                  child: const Text('Slide to unlock', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: _x == 0 ? const Duration(milliseconds: 250) : Duration.zero,
              curve: Curves.easeOutBack,
              left: _x,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) {
                  final next = (_x + d.delta.dx).clamp(0.0, max);
                  // A tick each quarter of the track, like a dial clicking into place.
                  if ((next / max * 4).floor() != (_x / max * 4).floor()) Haptics.select();
                  setState(() => _x = next);
                },
                onHorizontalDragEnd: (_) {
                  if (_x > max * 0.8 && !_done) {
                    _done = true;
                    setState(() => _x = max);
                    widget.onUnlock();
                  } else {
                    Haptics.light();
                    setState(() => _x = 0);
                  }
                },
                child: Container(
                  width: _h,
                  height: _h,
                  decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
                  child: Icon(_done ? Icons.lock_open_rounded : Icons.arrow_forward_rounded, color: Brand.onGold),
                ),
              ),
            ),
          ]),
        );
      });
}

class _Slide extends StatelessWidget {
  final (IconData, String, String) slide;
  final bool active;
  const _Slide(this.slide, {required this.active});

  @override
  Widget build(BuildContext context) => AnimatedSlide(
        offset: active ? Offset.zero : const Offset(0, 0.1),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: const Duration(milliseconds: 550),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (r) => Brand.gradient.createShader(r),
                  child: Icon(slide.$1, size: 44, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(slide.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 26, fontWeight: FontWeight.w700, height: 1.2)),
                const SizedBox(height: 12),
                Text(slide.$3, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16, height: 1.4)),
              ],
            ),
          ),
        ),
      );
}
