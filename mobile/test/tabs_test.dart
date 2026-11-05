import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/liquid.dart';

void main() {
  testWidgets('T-UI-05 a tab you leave fades out completely (v0.8.1 left it half-visible)', (tester) async {
    Widget app(int i) => MaterialApp(home: FadingTabs(index: i, children: const [Text('A'), Text('B'), Text('C')]));
    double opacityOf(String t) => tester.widget<AnimatedOpacity>(find.ancestor(of: find.text(t), matching: find.byType(AnimatedOpacity))).opacity;
    double shown(String t) =>
        tester.renderObject<RenderAnimatedOpacity>(find.ancestor(of: find.text(t), matching: find.byType(AnimatedOpacity))).opacity.value;

    await tester.pumpWidget(app(0));
    await tester.pumpWidget(app(2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect((opacityOf('A'), opacityOf('C')), (0.0, 1.0));
    expect(shown('A'), 0.0);
    expect(shown('C'), 1.0);
  });
}
