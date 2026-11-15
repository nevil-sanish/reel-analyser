import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_lock.dart';
import '../data/biometrics.dart';
import 'motion.dart';

/// Covers the app with the passcode screen when a passcode is set: at start, and at once whenever the app has been left
/// (home, another app, recent apps, screen off). The cover also hides the screen the moment the app leaves the front,
/// so the recent-apps picture shows nothing.
class LockGate extends StatefulWidget {
  final AppLock lock;
  final Widget child;
  final Biometrics biometrics;
  const LockGate({required this.lock, required this.child, this.biometrics = const NoBiometrics(), super.key});

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
  var _wasAway = false; // the app really left the front (not only lost focus to a system prompt)
  var _ask = 0; // bumped each time the lock screen is shown again, so it offers the fingerprint once

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
    if (s == AppLifecycleState.paused) {
      _wasAway = true;
      setState(() {
        _locked = true;
        _hidden = true;
      });
    } else if (s == AppLifecycleState.inactive) {
      setState(() => _hidden = true);
    } else if (s == AppLifecycleState.resumed) {
      setState(() {
        _hidden = false;
        if (_wasAway && _locked) _ask++;
        _wasAway = false;
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
          // The lock screen stays in the tree while the app only loses focus (the fingerprint prompt does that), so it is
          // still there to take the answer; a plain cover goes on top of it instead.
          child: Stack(children: [
            if (_locked && _ready)
              Positioned.fill(
                child: LockScreen(
                    lock: widget.lock, biometrics: widget.biometrics, ask: _ask, onUnlocked: () => setState(() => _locked = false)),
              ),
            if (!_ready || _hidden || !_locked) Positioned.fill(child: ColoredBox(color: Theme.of(context).colorScheme.surface)),
          ]),
        ),
    ]);
  }
}

class LockScreen extends StatefulWidget {
  final AppLock lock;
  final Biometrics biometrics;
  final int ask;
  final VoidCallback onUnlocked;
  const LockScreen({required this.lock, required this.biometrics, required this.ask, required this.onUnlocked, super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _c = TextEditingController();
  String? _msg;
  var _busy = false;
  Timer? _tick;
  var _bio = false;
  var _asking = false;

  @override
  void initState() {
    super.initState();
    _waiting();
    _startBiometric();
  }

  @override
  void didUpdateWidget(LockScreen old) {
    super.didUpdateWidget(old);
    if (old.ask != widget.ask && _bio) _askBiometric();
  }

  /// Offers fingerprint or face when the person turned it on and the phone still has one enrolled; asks once on its own.
  Future<void> _startBiometric() async {
    final on = await widget.lock.biometric && await widget.biometrics.available();
    if (!mounted) return;
    setState(() => _bio = on);
    if (on) await _askBiometric();
  }

  Future<void> _askBiometric() async {
    if (_asking) return;
    _asking = true;
    final ok = await widget.biometrics.check('Unlock Reel Analyser');
    _asking = false;
    if (!mounted || !ok) return;
    Haptics.success();
    widget.onUnlocked();
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
                if (_bio) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(onPressed: _askBiometric, icon: const Icon(Icons.fingerprint_rounded), label: const Text('Use fingerprint or face')),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
