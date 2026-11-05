import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/core/models.dart';
import 'package:reelbrain/ui/library_screen.dart';

void main() {
  testWidgets('T-UI-06 long-press starts selecting; a selected card shows a tick, an unselected one an empty circle', (tester) async {
    const r = Reel(url: 'u', app: 'youtube', title: 'Rice', summary: 's', savedAt: 0);
    var pressed = 0;
    Future<void> show(bool? selected) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: ReelCard(r, onTap: () {}, onLongPress: () => pressed++, selected: selected))));

    await show(null);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    await tester.longPress(find.text('Rice'));
    expect(pressed, 1);

    await show(true);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await show(false);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
  });
}
