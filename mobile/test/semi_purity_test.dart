import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The semi build must not contain Full-only code at all. Following every import/export/part from its entry point must never
// reach lib/full/, and only lib/main_full.dart (and lib/full/ itself) may import it.
final _dir = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''', multiLine: true);

String? _resolve(String from, String ref) {
  if (ref.startsWith('dart:')) return null;
  if (ref.startsWith('package:reelbrain/')) return 'lib/${ref.substring('package:reelbrain/'.length)}';
  if (ref.startsWith('package:')) return null;
  return File(from).parent.uri.resolve(ref).toFilePath().replaceFirst(RegExp('^${RegExp.escape(Directory.current.path)}/'), '');
}

Set<String> _reach(String entry) {
  final seen = <String>{}, todo = [entry];
  while (todo.isNotEmpty) {
    final f = todo.removeLast();
    if (!seen.add(f)) continue;
    final file = File(f);
    if (!file.existsSync()) continue;
    for (final m in _dir.allMatches(file.readAsStringSync())) {
      final r = _resolve(f, m.group(1)!);
      if (r != null) todo.add(r);
    }
  }
  return seen;
}

void main() {
  test('Semi entry point cannot reach lib/full/', () {
    final r = _reach('lib/main_semi.dart');
    expect(r, contains('lib/app.dart'), reason: 'the walk must actually follow imports');
    expect(r.where((f) => f.startsWith('lib/full/')), isEmpty);
  });

  test('only main_full.dart imports lib/full/ from outside it', () {
    final bad = <String>[];
    for (final e in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (e.path.startsWith('lib/full/') || e.path == 'lib/main_full.dart') continue;
      for (final m in _dir.allMatches(e.readAsStringSync())) {
        final r = _resolve(e.path, m.group(1)!);
        if (r != null && r.startsWith('lib/full/')) bad.add(e.path);
      }
    }
    expect(bad, isEmpty);
  });
}
