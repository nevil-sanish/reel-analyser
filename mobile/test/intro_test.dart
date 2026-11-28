import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  test('the blocker, goals and scroll pages are only in the full build; privacy is always last', () {
    final full = introSlides(blocker: true), semi = introSlides(blocker: false);
    expect(full.length, semi.length + 3);
    for (final t in ['Know your scroll', 'Block what pulls you in', 'Goals that count']) {
      expect(full.map((s) => s.title), contains(t));
      expect(semi.map((s) => s.title), isNot(contains(t)));
    }
    expect(full.last.points, contains('Settings → Erase all my data deletes everything'));
    expect(full.first.apps, containsAll(['instagram', 'youtube', 'linkedin', 'x', 'reddit', 'photo']));
  });

  testWidgets('intro: Next to the last page, a short slide springs back, a full slide unlocks', (tester) async {
    var done = 0;
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'HapticFeedback.vibrate') haptics.add(c.arguments);
      return null;
    });
    tester.view.physicalSize = const Size(1080, 2340); // a phone, not the 800×600 test default
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: Brand.theme(Brightness.dark), home: IntroScreen(onDone: () => done++)));
    await frames(tester, 40);
    for (var i = 0; i < introSlides(blocker: false).length - 1; i++) {
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
    expect(haptics, contains('HapticFeedbackType.heavyImpact')); // the unlock thud
  });
}
