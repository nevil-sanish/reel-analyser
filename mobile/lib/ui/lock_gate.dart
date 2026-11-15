import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_lock.dart';
import 'motion.dart';

/// Covers the app with the passcode screen when a passcode is set: at start, and when the app is opened again after
/// [grace] away. The cover also hides the screen the moment the app leaves the front, so the recent-apps picture shows nothing.
class LockGate extends StatefulWidget {
  final AppLock lock;
  final Widget child;
  final Duration grace;
  const LockGate({required this.lock, required this.child, this.grace = const Duration(seconds: 30), super.key});

  /// Told by Settings after the passcode is set, changed or removed.
  static final changed = ValueNotifier<int>(0);

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  var _ready = false; // until the first look at the setting, nothing of the app shows
  var _enabled = false;
  var _locked = false;
  var _hidden = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LockGate.changed.addListener(_refresh);
    _refresh(startLocked: true);
  }

  @override
  void dispose() {
    LockGate.changed.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh({bool startLocked = false}) async {
    final on = await widget.lock.enabled;
    if (!mounted) return;
    setState(() {
      _enabled = on;
      _ready = true;
      if (!on) {
        _locked = false;
        _hidden = false;
      } else if (startLocked) {
        _locked = true;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!_enabled) return;
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      _leftAt ??= DateTime.now();
      setState(() => _hidden = true);
    } else if (s == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      setState(() {
        if (left != null && DateTime.now().difference(left) >= widget.grace) _locked = true;
        _hidden = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cover = !_ready || (_enabled && (_locked || _hidden));
    return Stack(children: [
      widget.child,
      if (cover)
        Positioned.fill(
          child: _locked && _ready && !_hidden
              ? LockScreen(lock: widget.lock, onUnlocked: () => setState(() => _locked = false))
              : ColoredBox(color: Theme.of(context).colorScheme.surface),
        ),
    ]);
  }
}

class LockScreen extends StatefulWidget {
  final AppLock lock;
  final VoidCallback onUnlocked;
  const LockScreen({required this.lock, required this.onUnlocked, super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _c = TextEditingController();
  String? _msg;
  var _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _waiting();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// Shows the wait after too many wrong tries, counting down.
  Future<void> _waiting() async {
    final left = await widget.lock.waitLeft();
    if (!mounted) return;
    _tick?.cancel();
    if (left == null) return setState(() => _msg = null);
    setState(() => _msg = 'Too many tries. Wait ${left.inSeconds + 1} seconds.');
    _tick = Timer(const Duration(seconds: 1), _waiting);
  }

  Future<void> _go() async {
    final pin = _c.text;
    if (_busy || pin.isEmpty) return;
    setState(() => _busy = true);
    final ok = await widget.lock.verify(pin);
    if (!mounted) return;
    if (ok) {
      Haptics.success();
      return widget.onUnlocked();
    }
    Haptics.warning();
    _c.clear();
    setState(() {
      _busy = false;
      _msg = 'Wrong passcode.';
    });
    unawaited(_waiting().then((_) {
      if (mounted && _msg == null) setState(() => _msg = 'Wrong passcode.');
    }));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_rounded, size: 44, color: t.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Reel Analyser', style: t.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('Enter your passcode', style: t.textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextField(
                  controller: _c,
                  autofocus: true,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  style: t.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
                  decoration: const InputDecoration(counterText: ''),
                  onSubmitted: (_) => _go(),
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 8),
                  Text(_msg!, style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _go, child: const Text('Unlock'))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
