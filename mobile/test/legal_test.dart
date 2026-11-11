import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/legal_screen.dart';

void main() {
  String read(String n) => File('assets/legal/$n.md').readAsStringSync();

  test('the legal files use only what the in-app viewer shows (#, ##, -, **bold**)', () {
    for (final n in ['privacy', 'terms', 'disclaimer', 'support']) {
      for (final line in read(n).split('\n')) {
        expect(line.startsWith('###'), isFalse, reason: '$n: $line');
        expect(line.startsWith('|'), isFalse, reason: '$n has a table: $line');
        expect(
          line.startsWith('  - '),
          isFalse,
          reason: '$n has a nested bullet: $line',
        );
        expect(
          line.startsWith('* '),
          isFalse,
          reason: '$n: use "- " bullets: $line',
        );
      }
    }
  });

  test('they say what matters about the screen, the opt-in, the blocker and the paragraph', () {
    final p = read('privacy');
    expect(p, contains('never takes screenshots'));
    expect(p, contains('Allow reading the reel screens'));
    expect(p, contains('No photo is taken'));
    expect(p, contains('semi'));
    expect(p, isNot(contains('keeps recent screen text')));
    expect(read('terms'), contains('## 6. The Reel blocker'));
    expect(read('terms'), contains('## 7. Daily goals'));
    expect(read('terms'), contains('blocked for the next day only'));
    expect(read('privacy'), contains('Daily goals'));
    expect(read('privacy'), contains('When you press Organize'));
    expect(read('privacy'), contains('without any login or account'));
    expect(read('privacy'), contains('api.github.com'));
    expect(read('privacy'), contains('not an official API'));
    expect(read('privacy'), contains('written reason for changing a username'));
    expect(read('terms'), contains('Usernames are locked'));
    expect(read('terms'), contains('Changing or stopping goals takes a written paragraph'));
    expect(read('disclaimer'), contains('written reason'));
    expect(read('disclaimer'), contains('Daily goals'));
    expect(read('terms'), contains('can be bypassed'));
    expect(read('disclaimer'), contains('Not affiliated'));
    expect(read('disclaimer'), contains('Reel blocker'));
  });

  test('support is voluntary, refundable for 7 days by email, and every text points to the same contact', () {
    final s = read('support');
    expect(s, contains('will always stay free'));
    expect(s, contains('within 7 days'));
    expect(s, contains('nevilsanish@gmail.com'));
    expect(s, contains('transaction'));
    expect(s, contains('not tax-deductible'));
    expect(s, contains('nevilsanish@oksbi'));
    expect(read('terms'), contains('Support and Refund Policy'));
    expect(read('privacy'), contains('## 5. Support payments and emails to us'));
    expect(read('privacy'), contains('F-Droid do not check'));
    expect(read('disclaimer'), contains('## 7. Support payments'));
    for (final n in ['privacy', 'terms', 'disclaimer', 'support']) {
      expect(read(n), contains('nevilsanish@gmail.com'), reason: n);
    }
    // Every "section N" a text points to exists in the text it names.
    expect(read('support'), contains('Privacy Policy, section 5'));
    expect(read('disclaimer'), contains('sections 12 and 13'));
    expect(read('terms'), contains('## 12. No warranty'));
    expect(read('terms'), contains('## 13. Limitation of liability'));
  });

  testWidgets('every document renders', (t) async {
    for (final n in ['privacy', 'terms', 'disclaimer', 'support']) {
      late List<Widget> w;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              w = LegalScreen.render(c, read(n));
              return Scaffold(body: ListView(children: w));
            },
          ),
        ),
      );
      expect(w, isNotEmpty);
    }
  });
}
