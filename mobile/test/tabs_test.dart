import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/liquid.dart';

void main() {
  testWidgets('T-UI-05 a tab you leave is hidden at once and the tab you open is shown', (tester) async {
    Widget app(int i) => MaterialApp(home: FadingTabs(index: i, children: const [Text('A'), Text('B'), Text('C')]));

    await tester.pumpWidget(app(0));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('C'), findsNothing);
    await tester.pumpWidget(app(2));
    expect(find.text('A'), findsNothing);
    expect(find.text('C'), findsOneWidget);
    // The hidden tabs keep their state.
    expect(find.text('A', skipOffstage: false), findsOneWidget);
  });
}
