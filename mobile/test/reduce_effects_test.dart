import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/liquid.dart';
import 'package:reelbrain/ui/motion.dart';
import 'package:reelbrain/ui/theme.dart';

void main() {
  tearDown(() {
    Brand.reduceEffects.value = false;
    Haptics.enabled = true;
  });

  testWidgets('T-UI-07 the marble background is still and cards use no blur', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: Brand.theme(Brightness.light), home: const LiquidScaffold(body: Glass(child: Text('card')))));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.hasRunningAnimations, isFalse, reason: 'a still background costs nothing after the first frame');
    expect(find.text('card'), findsOneWidget);
  });

  testWidgets('T-UI-08 content rises into place, or shows at once when motion is reduced', (tester) async {
    Widget app() => MaterialApp(home: Reveal(child: const Text('hello')));
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 5));
    expect(tester.widget<FadeTransition>(find.descendant(of: find.byType(Reveal), matching: find.byType(FadeTransition))).opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);

    Brand.reduceEffects.value = true;
    await tester.pumpWidget(MaterialApp(home: Reveal(key: UniqueKey(), child: const Text('now'))));
    expect(tester.widget<FadeTransition>(find.descendant(of: find.byType(Reveal), matching: find.byType(FadeTransition))).opacity.value, 1);
  });

  testWidgets('T-UI-09 vibration goes through one switch', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'HapticFeedback.vibrate') calls.add('${c.arguments}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    Haptics.select();
    Haptics.light();
    expect(calls, hasLength(2));
    Haptics.enabled = false;
    Haptics.select();
    Haptics.heavy();
    await Haptics.success();
    expect(calls, hasLength(2), reason: 'off means no vibration at all');
  });

  testWidgets('T-UI-10 the theme is gold on marble and charcoal, with the bundled fonts', (tester) async {
    for (final b in Brightness.values) {
      final t = Brand.theme(b);
      expect(t.colorScheme.secondary, Brand.gold);
      expect(t.scaffoldBackgroundColor, b == Brightness.dark ? Brand.night : Brand.marble);
      expect(t.textTheme.headlineSmall?.fontFamily, 'Cormorant');
      expect(t.textTheme.bodyMedium?.fontFamily, 'Lato');
    }
  });
}
