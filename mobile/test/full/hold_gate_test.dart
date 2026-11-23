import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/full/hold_gate.dart';

void main() {

  testWidgets('the hold is 30 seconds', (t) async {
    expect(holdDuration, const Duration(seconds: 30));
  });

  testWidgets('holding the whole time accepts, and the fill grows', (t) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await askHold(c, title: 'Turn off', intro: 'Hold.', duration: const Duration(seconds: 30)),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    final g = await t.startGesture(const Offset(200, 400));
    await t.pump();
    await t.pump(const Duration(seconds: 15));
    final half = t.getSize(find.byKey(const ValueKey('hold-fill'))).height;
    expect(half, greaterThan(100));
    await t.pump(const Duration(seconds: 14));
    expect(result, isNull, reason: 'not yet at 30 s');
    await t.pump(const Duration(seconds: 2));
    await g.up();
    await t.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('lifting the finger drains the bar and does not accept', (t) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await askHold(c, title: 'Turn off', intro: 'Hold.', duration: const Duration(seconds: 30)),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    final g = await t.startGesture(const Offset(200, 400));
    await t.pump();
    await t.pump(const Duration(seconds: 29));
    await g.up();
    await t.pumpAndSettle();
    expect(result, isNull);
    expect(t.getSize(find.byKey(const ValueKey('hold-fill'))).height, 0);
    // a second, full hold still works afterwards
    final g2 = await t.startGesture(const Offset(200, 400));
    await t.pump();
    await t.pump(const Duration(seconds: 31));
    await g2.up();
    await t.pumpAndSettle();
    expect(result, isTrue);
  });
}
