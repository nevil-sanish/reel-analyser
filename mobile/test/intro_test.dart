import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/intro_screen.dart';
import 'package:reelbrain/ui/theme.dart';

/// The intro's ring and shimmer repeat forever, so pumpAndSettle never returns; run frames for a while instead.
Future<void> frames(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('intro: Next twice, a short slide springs back, a full slide unlocks', (tester) async {
    var done = 0;
    tester.view.physicalSize = const Size(1080, 2340); // a phone, not the 800×600 test default
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: Brand.theme(Brightness.dark), home: IntroScreen(onDone: () => done++)));
    await frames(tester, 40);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Next'));
      await frames(tester);
    }
    expect(find.text('Slide to unlock'), findsOneWidget);

    final thumb = find.byIcon(Icons.arrow_forward_rounded);
    await tester.drag(thumb, const Offset(60, 0));
    await frames(tester);
    expect(done, 0);

    await tester.drag(thumb, const Offset(1000, 0));
    await frames(tester);
    expect(done, 1);
  });
}
