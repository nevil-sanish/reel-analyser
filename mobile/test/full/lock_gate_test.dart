import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/full/app_lock.dart';
import 'package:reelbrain/full/biometrics.dart';
import 'package:reelbrain/full/lock_gate.dart';

class _Mem implements LockStorage {
  final m = <String, String>{};
  @override
  Future<String?> readLock(String k) async => m[k];
  @override
  Future<void> writeLock(String k, String? v) async => v == null || v.isEmpty ? m.remove(k) : m[k] = v;
}

class _Bio implements Biometrics {
  final bool pass;
  var asked = 0;
  _Bio(this.pass);
  @override
  Future<bool> available() async => true;
  @override
  Future<bool> check(String reason) async {
    asked++;
    return pass;
  }
}

class _SlowBio implements Biometrics {
  final done = Completer<bool>();
  @override
  Future<bool> available() async => true;
  @override
  Future<bool> check(String reason) => done.future;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
}

void main() {
  testWidgets('leaving the app locks it at once; a good fingerprint opens it, a failed one leaves the passcode', (tester) async {
    final lock = AppLock(_Mem());
    await tester.runAsync(() async {
      await lock.set('4821');
      await lock.setBiometric(true);
    });
    final bad = _Bio(false);
    await tester.pumpWidget(MaterialApp(home: LockGate(lock: lock, biometrics: bad, child: const Text('the app'))));
    await _settle(tester);
    expect(bad.asked, 1);
    expect(find.text('Enter your passcode'), findsOneWidget);
    expect(find.text('Use fingerprint or face'), findsOneWidget);

    final good = _Bio(true);
    await tester.pumpWidget(MaterialApp(home: LockGate(key: UniqueKey(), lock: lock, biometrics: good, child: const Text('the app'))));
    await _settle(tester);
    expect(find.text('Enter your passcode'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(good.asked, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the system prompt takes focus while it is shown; its answer still unlocks the app', (tester) async {
    final lock = AppLock(_Mem());
    await tester.runAsync(() async {
      await lock.set('4821');
      await lock.setBiometric(true);
    });
    final bio = _SlowBio();
    await tester.pumpWidget(MaterialApp(home: LockGate(lock: lock, biometrics: bio, child: const Text('the app'))));
    await _settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    bio.done.complete(true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(find.text('Enter your passcode'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('without the biometric switch there is no fingerprint button', (tester) async {
    final lock = AppLock(_Mem());
    await tester.runAsync(() => lock.set('4821'));
    final bio = _Bio(true);
    await tester.pumpWidget(MaterialApp(home: LockGate(lock: lock, biometrics: bio, child: const Text('the app'))));
    await _settle(tester);
    expect(bio.asked, 0);
    expect(find.text('Use fingerprint or face'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('with a passcode the app is covered until it is entered; without one it opens straight', (tester) async {
    final lock = AppLock(_Mem());
    await tester.runAsync(() => lock.set('4821'));
    await tester.pumpWidget(MaterialApp(home: LockGate(lock: lock, child: const Text('the app'))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Enter your passcode'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text('Unlock'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump();
    expect(find.text('Wrong passcode.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4821');
    await tester.tap(find.text('Unlock'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump();
    expect(find.text('Enter your passcode'), findsNothing);

    final open = AppLock(_Mem());
    await tester.pumpWidget(MaterialApp(home: LockGate(lock: open, child: const Text('the app'))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Enter your passcode'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
