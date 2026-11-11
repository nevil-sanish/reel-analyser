import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/source_icon.dart';

void main() {
  testWidgets('each source gets its own badge, with a spoken name', (t) async {
    await t.pumpWidget(const MaterialApp(home: Row(children: [SourceIcon('instagram'), SourceIcon('youtube'), SourceIcon('photo')])));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.photo_rounded), findsOneWidget);
    expect(find.byIcon(Icons.movie_rounded), findsNothing);
    expect(find.bySemanticsLabel('Instagram'), findsOneWidget);
    expect(find.bySemanticsLabel('YouTube'), findsOneWidget);
  });
}
