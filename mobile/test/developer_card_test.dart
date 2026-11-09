import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/developer_card.dart';

void main() {
  testWidgets(
    'shows the developer, the GitHub link and the thanks, and opens GitHub',
    (t) async {
      String? opened;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DeveloperCard(onOpen: (u) => opened = u)),
        ),
      );
      expect(find.text('Nevil Mathew Sanish'), findsOneWidget);
      expect(find.textContaining('Sanjay S'), findsOneWidget);
      expect(find.textContaining('Ashin Antony'), findsOneWidget);
      expect(find.textContaining('Harry SP'), findsOneWidget);
      await t.tap(find.text('GitHub'));
      expect(opened, 'https://github.com/nevil-sanish');
    },
  );
}
