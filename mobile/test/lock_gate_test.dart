import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/data/app_lock.dart';
import 'package:reelbrain/ui/lock_gate.dart';

class _Mem implements LockStorage {
  final m = <String, String>{};
  @override
  Future<String?> readLock(String k) async => m[k];
  @override
  Future<void> writeLock(String k, String? v) async => v == null || v.isEmpty ? m.remove(k) : m[k] = v;
}

void main() {
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
