import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/app_services.dart';
import 'package:reelbrain/full/limits_screen.dart';

void main() {
  testWidgets('add an app, save, and the bar shows', (tester) async {
    String? active;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('reelbot/counter'), (call) async {
      switch (call.method) {
        case 'limitsState':
          return {'active': active, 'pending': null, 'pendingFrom': 0, 'used': {'app:com.a': 5 * 60000}, 'usageAccess': true};
        case 'limitsSave':
          active = call.arguments['items'] as String;
          return 'ok';
        case 'installedApps':
          return [{'pkg': 'com.a', 'label': 'Alpha'}];
        case 'detectionConsent':
          return true;
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LimitsScreen(_NoServices()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add app'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Turn the limits on'), findsOneWidget);
    await tester.tap(find.text('Turn the limits on'));
    await tester.pumpAndSettle();
    expect(find.text('On'), findsOneWidget);
    expect(find.textContaining('5 min of 30 min'), findsOneWidget);
  });
}

class _NoServices implements AppServices {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
