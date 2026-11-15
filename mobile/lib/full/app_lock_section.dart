import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import 'app_lock.dart';
import 'biometrics.dart';

import 'lock_gate.dart';

/// Settings → App lock: set, change or remove the passcode that opens the app.
class AppLockSection extends StatefulWidget {
  final AppServices services;
  const AppLockSection(this.services, {super.key});

  @override
  State<AppLockSection> createState() => _AppLockSectionState();
}

class _AppLockSectionState extends State<AppLockSection> {
  final _bridge = BridgeBiometrics();
  late final _lock = AppLock(KeyLockStorage(widget.services.keys), hasher: AppLock.nativeHash);
  bool? _on;
  var _bio = false;
  var _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await _lock.enabled;
    final bio = await _lock.biometric;
    final avail = on && await _bridge.available();
    if (mounted) {
      setState(() {
        _on = on;
        _bio = bio && avail;
        _bioAvailable = avail;
      });
    }
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Asks for one or more passcodes; null when cancelled.
  Future<List<String>?> _ask(String title, List<String> labels, {String? note}) {
    final cs = [for (final _ in labels) TextEditingController()];
    return showDialog<List<String>>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (note != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(note)),
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: cs[i],
                  autofocus: i == 0,
                  obscureText: true,
                  maxLength: 8,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: labels[i], counterText: ''),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, [for (final c in cs) c.text]), child: const Text('OK')),
        ],
      ),
    );
  }

  /// True when [current] is the passcode; otherwise says why not.
  Future<bool> _right(String current) async {
    if (await _lock.verify(current)) return true;
    final wait = await _lock.waitLeft();
    _say(wait == null ? 'Wrong passcode.' : 'Too many tries. Wait ${wait.inSeconds + 1} seconds.');
    return false;
  }

  Future<void> _setNew(String title) async {
    final r = await _ask(title, const ['New passcode (4 to 8 digits)', 'Repeat it'],
        note: 'If you forget it, the only way back in is to clear the app\'s data in Android settings or reinstall, which deletes your notes. Export a backup first.');
    if (r == null || !mounted) return;
    final bad = AppLock.check(r[0]);
    if (bad != null) return _say(bad);
    if (r[0] != r[1]) return _say('The two passcodes are not the same.');
    await _lock.set(r[0]);
    LockGate.changed.value++;
    await _load();
    if (mounted) _say('The passcode is on.');
  }

  Future<void> _change() async {
    final r = await _ask('Change the passcode', const ['Current passcode']);
    if (r == null || !mounted || !await _right(r[0]) || !mounted) return;
    await _setNew('New passcode');
  }

  Future<void> _toggleBio(bool want) async {
    if (want && !await _bridge.check('Turn on fingerprint or face unlock')) return _say('Not turned on: the check did not pass.');
    await _lock.setBiometric(want);
    await _load();
  }

  Future<void> _remove() async {
    final r = await _ask('Remove the passcode', const ['Current passcode']);
    if (r == null || !mounted || !await _right(r[0])) return;
    await _lock.remove();
    LockGate.changed.value++;
    await _load();
    if (mounted) _say('The passcode is removed.');
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        on
            ? 'The passcode is on. The app asks for it when you open it, and every time you come back after leaving it. Sharing a reel to the app still works without it.'
            : 'Ask for a passcode before the app opens. It only hides what is in the app: sharing a reel to it and the background analysis keep working.',
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (!on) FilledButton.icon(onPressed: () => _setNew('Set a passcode'), icon: const Icon(Icons.lock_outline_rounded), label: const Text('Set a passcode')),
        if (on) OutlinedButton(onPressed: _change, child: const Text('Change')),
        if (on) OutlinedButton(onPressed: _remove, child: const Text('Remove')),
      ]),
      if (on && _bioAvailable)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Unlock with fingerprint or face'),
          subtitle: const Text('The passcode still works, and is the way in if the fingerprint fails.'),
          value: _bio,
          onChanged: _toggleBio,
        ),
    ]);
  }
}
