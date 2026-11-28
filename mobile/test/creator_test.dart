import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/core/creator.dart';
import 'package:reelbrain/core/models.dart';

Creator? of(String app, String author) => Creator.of(Reel(url: 'u', app: app, title: 't', summary: '', author: author, savedAt: 1));

void main() {
  test('Instagram handle gets an @ and its profile', () {
    final c = of('instagram', 'omkar.docs')!;
    expect((c.name, c.platform, c.profile), ('@omkar.docs', 'Instagram', 'https://www.instagram.com/omkar.docs/'));
  });

  test('X keeps the display name and links the handle', () {
    final c = of('x', 'NASA (@NASA)')!;
    expect((c.name, c.profile), ('NASA (@NASA)', 'https://x.com/NASA'));
  });

  test('Reddit user and a LinkedIn name (no link)', () {
    expect(of('reddit', 'u/galratner')!.profile, 'https://www.reddit.com/user/galratner/');
    final l = of('linkedin', "SWAG Developer's Club")!;
    expect((l.name, l.platform, l.profile), ("SWAG Developer's Club", 'LinkedIn', null));
  });

  test('no author or a photo shows nothing', () {
    expect(of('instagram', ''), isNull);
    expect(of('photo', 'me'), isNull);
  });

  test('a name that is not a handle is never made into a link', () {
    expect(of('instagram', 'Some Name / ad')!.profile, isNull);
  });

  test('YouTube: a handle gets @ and its channel, a plain name does not', () {
    final c = of('youtube', 'mkbhd')!;
    expect((c.name, c.profile), ('@mkbhd', 'https://www.youtube.com/@mkbhd'));
    expect(of('youtube', 'Marques Brownlee')!.profile, isNull);
  });
}
