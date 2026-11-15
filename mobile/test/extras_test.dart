import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/data/export.dart';

void main() {
  test('a backup carries the build\'s extras and reads them back', () {
    final json = exportJson(const [], const [], null, const {}, {
      'reelLimits': {'mode': 'shared'},
      'timeLimits': [{'kind': 'app', 'id': 'com.a', 'label': 'A', 'limitMin': 5}],
    });
    final e = extrasOf(json);
    expect(e.keys, containsAll(['reelLimits', 'timeLimits']));
    expect((e['timeLimits'] as List).length, 1);
  });

  test('no extras: the file has none and the reader gives an empty map', () {
    final json = exportJson(const []);
    expect(json.contains('extras'), isFalse);
    expect(extrasOf(json), isEmpty);
    expect(extrasOf('[]'), isEmpty);
  });
}
