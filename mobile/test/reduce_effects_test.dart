import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/liquid.dart';
import 'package:reelbrain/ui/theme.dart';

void main() {
  tearDown(() => Brand.reduceEffects.value = false);

  testWidgets('T-UI-07 Reduce effects stops the background and drops the blur, and turning it off restores both',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LiquidScaffold(body: Glass(child: Text('card')))));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);

    Brand.reduceEffects.value = true;
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('card'), findsOneWidget);

    Brand.reduceEffects.value = false;
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
  });
}
