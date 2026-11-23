import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/liquid.dart';

/// How long a finger must stay down to change or turn off a block.
const holdDuration = Duration(seconds: 30);

/// Asks the person to press and hold a finger on the screen for 30 seconds. A bar fills the whole screen while the finger is down
/// and drains if it lifts, so the wait cannot be skipped or split up. Nothing is typed, stored or sent. Resolves true when the bar
/// is full, false when the person backs out.
Future<bool> askHold(
  BuildContext context, {
  required String title,
  required String intro,
  Duration duration = holdDuration,
}) async =>
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _HoldScreen(title, intro, duration)),
    ) ??
    false;

class _HoldScreen extends StatefulWidget {
  final String title, intro;
  final Duration duration;
  const _HoldScreen(this.title, this.intro, this.duration);

  @override
  State<_HoldScreen> createState() => _HoldScreenState();
}

class _HoldScreenState extends State<_HoldScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener(_status);
  final _down = <int>{};
  bool _done = false;

  void _status(AnimationStatus s) {
    if (s == AnimationStatus.completed && !_done) {
      _done = true;
      HapticFeedback.heavyImpact();
      Navigator.pop(context, true);
    }
  }

  void _press(PointerDownEvent e) {
    _down.add(e.pointer);
    if (!_done) _c.forward();
  }

  void _lift(PointerEvent e) {
    _down.remove(e.pointer);
    if (_down.isEmpty && !_done) {
      // Draining is faster than filling, so letting go always costs more than it gained.
      _c.animateBack(
        0,
        duration: widget.duration * 0.15,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LiquidScaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _press,
        onPointerUp: _lift,
        onPointerCancel: _lift,
        child: SizedBox.expand(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final left =
                  (widget.duration.inMilliseconds * (1 - _c.value) / 1000)
                      .ceil();
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: _c.value,
                        widthFactor: 1,
                        child: ColoredBox(
                          color: t.colorScheme.primary.withValues(alpha: 0.35),
                          key: const ValueKey('hold-fill'),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.intro, style: t.textTheme.bodyMedium),
                        const Spacer(),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.fingerprint_rounded,
                                size: 96,
                                color: t.colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _c.value == 0
                                    ? 'Press and hold anywhere on the screen'
                                    : 'Keep holding… $left s',
                                textAlign: TextAlign.center,
                                style: t.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Hold for ${widget.duration.inSeconds} seconds. If you lift your finger, the bar starts again.',
                                textAlign: TextAlign.center,
                                style: t.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
