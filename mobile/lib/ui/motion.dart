import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Every tap, selection and result goes through here, so Settings → Vibration turns them all off at once.
class Haptics {
  static bool enabled = true;

  static void light() => enabled ? HapticFeedback.lightImpact() : null;
  static void select() => enabled ? HapticFeedback.selectionClick() : null;
  static void medium() => enabled ? HapticFeedback.mediumImpact() : null;
  static void heavy() => enabled ? HapticFeedback.heavyImpact() : null;

  /// Two soft pulses: something worked.
  static Future<void> success() async {
    if (!enabled) return;
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.mediumImpact();
  }

  /// A firm pulse: something was refused.
  static void warning() => enabled ? HapticFeedback.heavyImpact() : null;
}

/// Shrinks a little under the finger and springs back, with a light tap, for anything pressable.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  const Pressable({required this.child, this.onTap, this.onLongPress, this.scale = 0.97, this.haptic = true, super.key});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) Haptics.light();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down && !Brand.reduceEffects.value ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 90 : 220),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      );
}

/// Fades and rises into place when first shown, one after another by [index]. Shown at once when motion is reduced.
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  final bool animate;
  const Reveal({required this.child, this.index = 0, this.animate = true, super.key});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (!widget.animate || Brand.reduceEffects.value) {
      _c.value = 1;
    } else {
      Future<void>.delayed(Duration(milliseconds: 40 * widget.index.clamp(0, 10)), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Rises into place without a fade: a fade makes every card an offscreen layer while it plays, which dropped frames.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (_, child) => Transform.translate(offset: Offset(0, 16 * (1 - _a.value)), child: child),
      );
}

/// A number that counts up to its value, for the figures on Insights.
class CountUp extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final String Function(num) format;
  const CountUp(this.value, {this.style, this.format = _plain, super.key});

  static String _plain(num v) => '${v.round()}';

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: Brand.reduceEffects.value ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(format(v), style: style),
      );
}

/// A resting placeholder while something loads: a pale gold bar. It does not animate: a sweeping light on every bar of every
/// placeholder meant dozens of tickers and repaints exactly while a screen was opening.
class Skeleton extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;
  const Skeleton({this.height = 16, this.width, this.radius = 10, super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), color: Brand.gold.withValues(alpha: dark ? 0.16 : 0.2)),
    );
  }
}
