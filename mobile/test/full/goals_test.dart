import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reelbrain/data/library_db.dart';
import 'package:reelbrain/full/goal_store.dart';
import 'package:reelbrain/full/goals.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('rules', () {
    const gh = Goal('github', 'octo', 2), cf = Goal('codeforces', 'tourist', 1), lc = Goal('leetcode', 'lee', 2);
    Map<String, Count> counts({int g = 5, int c = 1, int l = 2}) => {'github': Count.ok(g), 'codeforces': Count.ok(c), 'leetcode': Count.ok(l)};

    test('met only when every goal is met', () {
      expect(dayMet([gh, cf, lc], counts()), isTrue);
      expect(dayMet([gh, cf, lc], counts(c: 0)), isFalse);
      expect(dayMet([gh], counts(g: 1)), isFalse);
      expect(dayMet([], {}), isTrue);
    });

    test('a site that could not be read is never a miss', () {
      expect(dayMet([gh, cf], {'github': Count.ok(5), 'codeforces': const Count.fail('x')}), isNull);
      expect(dayMet([gh, cf], {'github': Count.ok(1), 'codeforces': const Count.fail('x')}), isFalse, reason: 'one goal is surely missed');
      expect(dayMet([gh], {'github': const Count.ok(1, exact: false)}), isNull, reason: 'at least 1 might be 2');
      expect(dayMet([gh], {'github': const Count.ok(3, exact: false)}), isTrue, reason: 'at least 3 already meets 2');
    });

    test('the penalty is 1, then 2, then 4 days, and a met day ends the run', () {
      var p = const Penalty(0, null);
      p = applyDay(p, '2026-11-02', false);
      expect((p.streak, p.until), (1, '2026-11-03'));
      p = applyDay(p, '2026-11-03', false);
      expect((p.streak, p.until), (2, '2026-11-05'));
      p = applyDay(p, '2026-11-04', false);
      expect((p.streak, p.until), (3, '2026-11-08'));
      p = applyDay(p, '2026-11-05', false);
      expect(p.streak, 4);
      expect(p.until, '2026-11-09', reason: 'never more than 4 days from the miss');
      p = applyDay(p, '2026-11-06', true);
      expect((p.streak, p.until), (0, '2026-11-09'), reason: 'a met day resets the run but does not lift a block');
      p = applyDay(p, '2026-11-07', null);
      expect(p.streak, 0, reason: 'unknown changes nothing');
      p = applyDay(p, '2026-11-20', false);
      expect((p.streak, p.until), (1, '2026-11-21'));
    });

    test('a shorter new block never shortens one already running', () {
      final p = applyDay(const Penalty(2, '2026-11-12'), '2026-11-03', false);
      expect(p.until, '2026-11-12');
    });

    test('dates and offsets', () {
      expect(addDays('2026-11-30', 1), '2026-12-01');
      expect(addDays('2026-01-01', -1), '2025-12-31');
      expect(dateOf(DateTime(2026, 3, 5)), '2026-03-05');
      expect(isoWithOffset(DateTime(2026, 11, 9, 0, 0, 0)), matches(RegExp(r'^2026-11-09T00:00:00[+-]\d\d:\d\d$')));
    });

    test('handles are checked before they go into an address', () {
      expect(validHandle('github', 'nevil-sanish'), isTrue);
      expect(validHandle('github', '-bad'), isFalse);
      expect(validHandle('github', 'a b'), isFalse);
      expect(validHandle('github', 'x/../y'), isFalse);
      expect(validHandle('codeforces', 'ab'), isFalse);
      expect(validHandle('codeforces', 'tourist'), isTrue);
      expect(validHandle('leetcode', 'lee_215-x'), isTrue);
      expect(validHandle('leetcode', 'a&b=c'), isFalse);
      expect(validHandle('leetcode', ''), isFalse);
    });

    test('a config round trip drops anything malformed', () {
      final c = GoalConfig([gh, cf], {'instagram'});
      final back = GoalConfig.parse(c.toJson())!;
      expect(back.goals.map((g) => (g.source, g.handle, g.target)), [('github', 'octo', 2), ('codeforces', 'tourist', 1)]);
      expect(back.blockApps, {'instagram'});
      final odd = GoalConfig.parse('{"goals":[{"source":"github","handle":"a b","target":2},{"source":"x","handle":"abc","target":1},{"source":"leetcode","handle":"ok","target":0},{"source":"leetcode","handle":"ok","target":3}],"blockApps":["instagram","tiktok"]}')!;
      expect(odd.goals.length, 1);
      expect(odd.goals.single.target, 3);
      expect(odd.blockApps, {'instagram'});
      expect(GoalConfig.parse('nonsense'), isNull);
    });
  });

  group('fetchers', () {
    final start = DateTime(2026, 11, 9);
    int t(int h, [int m = 0]) => DateTime(2026, 11, 9, h, m).millisecondsSinceEpoch ~/ 1000;

    test('only the three public hosts are called, with the handle and nothing else', () async {
      final seen = <Uri>[];
      final seenHeaders = <Map<String, String>>[];
      final client = MockClient((r) async {
        seen.add(r.url);
        seenHeaders.add(r.headers);
        if (r.url.host == 'api.github.com') return http.Response(jsonEncode({'total_count': 3, 'incomplete_results': false, 'items': []}), 200);
        if (r.url.host == 'codeforces.com') return http.Response(jsonEncode({'status': 'OK', 'result': []}), 200);
        return http.Response(jsonEncode({'data': {'matchedUser': {'username': 'x'}, 'recentAcSubmissionList': []}}), 200);
      });
      final f = GoalFetcher(client);
      await f.day(const Goal('github', 'octo', 1), start);
      await f.day(const Goal('codeforces', 'tourist', 1), start);
      await f.day(const Goal('leetcode', 'lee215', 1), start);
      expect(seen.map((u) => u.host).toSet(), goalHosts);
      expect(seen.every((u) => u.scheme == 'https'), isTrue);
      for (final h in seenHeaders) {
        expect(h.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
        expect(h.keys.map((k) => k.toLowerCase()), isNot(contains('cookie')));
        expect(h['User-Agent'], GoalFetcher.userAgent);
      }
      expect(seen.first.queryParameters['q'], contains('author:octo'));
      expect(seen.first.queryParameters['q'], matches(RegExp(r'author-date:2026-11-09T00:00:00[+-]\d\d:\d\d\.\.2026-11-09T23:59:59')));
    });

    test('GitHub: the count, an unknown user, a rate limit', () async {
      Future<Count> with_(int code, Object body) => GoalFetcher(MockClient((_) async => http.Response(jsonEncode(body), code))).day(const Goal('github', 'octo', 1), start);
      expect((await with_(200, {'total_count': 4, 'incomplete_results': false})).n, 4);
      expect((await with_(200, {'total_count': 4, 'incomplete_results': true})).exact, isFalse);
      expect((await with_(422, {'message': 'Validation Failed'})).error, contains('username'));
      expect((await with_(403, {'message': 'rate limit'})).error, contains('limiting'));
    });

    test('Codeforces: different accepted problems that day, local day only', () async {
      final r = [
        {'creationTimeSeconds': t(23, 10), 'verdict': 'OK', 'problem': {'contestId': 1, 'index': 'A'}},
        {'creationTimeSeconds': t(22, 0), 'verdict': 'WRONG_ANSWER', 'problem': {'contestId': 1, 'index': 'B'}},
        {'creationTimeSeconds': t(21, 0), 'verdict': 'OK', 'problem': {'contestId': 1, 'index': 'A'}}, // the same problem again
        {'creationTimeSeconds': t(12, 0), 'verdict': 'OK', 'problem': {'contestId': 2, 'index': 'C'}},
        {'creationTimeSeconds': t(0, 0) - 60, 'verdict': 'OK', 'problem': {'contestId': 3, 'index': 'D'}}, // the day before
      ];
      final c = await GoalFetcher(MockClient((_) async => http.Response(jsonEncode({'status': 'OK', 'result': r}), 200))).day(const Goal('codeforces', 'tourist', 2), start);
      expect(c.n, 2);
      expect(c.exact, isTrue);
      final bad = await GoalFetcher(MockClient((_) async => http.Response(jsonEncode({'status': 'FAILED', 'comment': 'handle: User with handle x not found'}), 400))).day(const Goal('codeforces', 'tourist', 2), start);
      expect(bad.error, contains('does not know'));
    });

    test('Codeforces: a full page that does not reach back to the day is only "at least"', () async {
      final r = [for (var i = 0; i < 100; i++) {'creationTimeSeconds': t(23) - i * 60, 'verdict': 'OK', 'problem': {'contestId': i, 'index': 'A'}}];
      final c = await GoalFetcher(MockClient((_) async => http.Response(jsonEncode({'status': 'OK', 'result': r}), 200))).day(const Goal('codeforces', 'tourist', 1), start);
      expect(c.n, 100);
      expect(c.exact, isFalse, reason: 'the 100 submissions only reach back to 21:20, so the morning may be missing: "at least"');
    });

    test('LeetCode: different problems that day, an unknown user', () async {
      Map<String, Object?> sub(String slug, int ts) => {'titleSlug': slug, 'timestamp': '$ts'};
      final ok = {'data': {'matchedUser': {'username': 'x'}, 'recentAcSubmissionList': [sub('a', t(20)), sub('a', t(19)), sub('b', t(10)), sub('c', t(0) - 100)]}};
      final c = await GoalFetcher(MockClient((_) async => http.Response(jsonEncode(ok), 200))).day(const Goal('leetcode', 'lee215', 2), start);
      expect(c.n, 2);
      expect(c.exact, isTrue);
      final none = await GoalFetcher(MockClient((_) async => http.Response(jsonEncode({'errors': [{'message': 'That user does not exist.'}], 'data': {'matchedUser': null}}), 200))).day(const Goal('leetcode', 'nobody', 1), start);
      expect(none.error, contains('does not know'));
    });

    test('network trouble is a failed read, not a crash', () async {
      final c = await GoalFetcher(MockClient((_) async => throw http.ClientException('offline'))).day(const Goal('github', 'octo', 1), start);
      expect(c.n, isNull);
      expect(c.error, isNotNull);
      final bad = await GoalFetcher(MockClient((_) async => http.Response('not json', 200))).day(const Goal('github', 'octo', 1), start);
      expect(bad.n, isNull);
      expect((await GoalFetcher(MockClient((_) async => http.Response('{}', 200))).day(const Goal('github', 'a b', 1), start)).error, isNotNull, reason: 'a bad handle is refused before any request');
    });

    test('a list is fetched once for several days', () async {
      var calls = 0;
      final f = GoalFetcher(MockClient((_) async {
        calls++;
        return http.Response(jsonEncode({'status': 'OK', 'result': []}), 200);
      }));
      for (var d = 1; d <= 5; d++) {
        await f.day(const Goal('codeforces', 'tourist', 1), DateTime(2026, 11, d));
      }
      expect(calls, 1);
    });
  });

  group('engine', () {
    late LibraryDb ldb;
    late GoalStore db;
    setUp(() async {
      ldb = await LibraryDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      db = await GoalStore.of(ldb);
    });
    tearDown(() => ldb.close());

    GoalFetcher fetcher(Map<String, int> byDay) => GoalFetcher(MockClient((r) async {
          // GitHub search: the day is in the query; answer from byDay by date.
          final q = r.url.queryParameters['q']!;
          final day = RegExp(r'author-date:(\d{4}-\d\d-\d\d)').firstMatch(q)!.group(1)!;
          return http.Response(jsonEncode({'total_count': byDay[day] ?? 0, 'incomplete_results': false}), 200);
        }));

    GoalEngine engine(GoalFetcher f, DateTime now, List<(Penalty, Set<String>)> out) =>
        GoalEngine(storeFuture: Future.value(db), fetcher: f, now: () => now, publish: (p, a) async => out.add((p, a)));

    Future<void> setGoals(String from, {int target = 1, Set<String> apps = const {'instagram'}}) =>
        db.saveGoalConfig(from, GoalConfig([Goal('github', 'octo', target)], apps).toJson());

    test('nothing is judged until the day has ended, and a day is judged once', () async {
      await setGoals('2026-11-09');
      final out = <(Penalty, Set<String>)>[];
      var p = await engine(fetcher({}), DateTime(2026, 11, 9, 23, 59), out).run();
      expect(p.streak, 0);
      expect(await db.lastGoalDay(), isNull);
      p = await engine(fetcher({}), DateTime(2026, 11, 10, 0, 10), out).run();
      expect(await db.lastGoalDay(), isNull, reason: 'wait 20 minutes after midnight for the day to settle');
      p = await engine(fetcher({}), DateTime(2026, 11, 10, 0, 30), out).run();
      expect((p.streak, p.until), (1, '2026-11-10'));
      p = await engine(fetcher({}), DateTime(2026, 11, 10, 9), out).run();
      expect(p.streak, 1, reason: 'the same day is not judged twice');
    });

    test('misses in a row grow the block, a met day ends the run', () async {
      await setGoals('2026-11-01');
      final out = <(Penalty, Set<String>)>[];
      final f = fetcher({'2026-11-04': 1}); // the goal is met on the 4th only
      final p = await engine(f, DateTime(2026, 11, 7, 1), out).run();
      // days 1..6 judged (floor is 7 days back): miss, miss, miss, met, miss, miss
      final days = await db.goalDays();
      expect(days.map((d) => d.$3).toList().reversed, [false, false, false, true, false, false]);
      expect(days.map((d) => d.$4).toList().reversed, [1, 2, 3, 0, 1, 2]);
      expect(p.streak, 2);
      expect(p.until, '2026-11-08', reason: 'the 6th missed twice in a row: 2 days after the 6th');
      expect(out.last.$2, {'instagram'});
    });

    test('a site that cannot be read is retried, and only dropped after three days', () async {
      await setGoals('2026-11-01');
      final broken = GoalFetcher(MockClient((_) async => throw http.ClientException('offline')));
      final out = <(Penalty, Set<String>)>[];
      var p = await engine(broken, DateTime(2026, 11, 2, 1), out).run();
      expect((p.streak, p.until), (0, null));
      expect(await db.lastGoalDay(), isNull, reason: 'still waiting, no penalty');
      p = await engine(broken, DateTime(2026, 11, 5, 1), out).run();
      expect(p.streak, 0, reason: 'dropped as unknown, never a miss');
      expect((await db.goalDays()).every((d) => d.$3 == null), isTrue);
    });

    test('a day is judged by the goals that were in force on it', () async {
      await setGoals('2026-11-01', target: 3);
      await setGoals('2026-11-02', target: 1); // lowered from the 2nd on
      final out = <(Penalty, Set<String>)>[];
      await engine(fetcher({'2026-11-01': 1, '2026-11-02': 1}), DateTime(2026, 11, 3, 1), out).run();
      final d = {for (final x in await db.goalDays()) x.$1: x.$3};
      expect(d['2026-11-01'], isFalse, reason: '1 commit is not enough for the old target of 3');
      expect(d['2026-11-02'], isTrue);
    });

    test('no goals, no work, and erasing clears them', () async {
      final out = <(Penalty, Set<String>)>[];
      await engine(fetcher({}), DateTime(2026, 11, 3, 1), out).run();
      expect(out, isEmpty);
      await setGoals('2026-11-01');
      await engine(fetcher({}), DateTime(2026, 11, 3, 1), out).run();
      expect(out, isNotEmpty);
      await db.eraseAll();
      expect(await db.latestGoalConfigJson(), isNull);
      expect(await db.goalDays(), isEmpty);
    });
  });

  group('midnight schedule', () {
    test('next check is 00:20, today if it is still ahead, else tomorrow', () {
      expect(nextMidnightCheck(DateTime(2026, 11, 9, 0, 5)), DateTime(2026, 11, 9, 0, 20));
      expect(nextMidnightCheck(DateTime(2026, 11, 9, 0, 20)), DateTime(2026, 11, 10, 0, 20));
      expect(nextMidnightCheck(DateTime(2026, 11, 9, 22, 0)), DateTime(2026, 11, 10, 0, 20));
      expect(nextMidnightCheck(DateTime(2026, 12, 31, 23, 59)), DateTime(2027, 1, 1, 0, 20));
      expect(nextMidnightCheck(DateTime(2026, 2, 28, 12)), DateTime(2026, 3, 1, 0, 20));
    });
  });

  group('changing a username', () {
    test('cooling off: first ask waits, a later day is ready, a refusal starts the wait again', () {
      expect(changeStep(null, '2026-11-09'), ChangeStep.start);
      expect(changeStep('2026-11-09', '2026-11-09'), ChangeStep.wait);
      expect(changeStep('2026-11-09', '2026-11-10'), ChangeStep.ready);
      expect(changeStep('2026-11-10', '2026-11-10'), ChangeStep.wait); // refused today
    });

    test('verdict parser accepts only a clear boolean', () {
      expect(parseVerdict('{"valid": true, "reason": "ok"}')!.valid, isTrue);
      expect(parseVerdict('```json\n{"valid": false, "reason": "vague"}\n```')!.reason, 'vague');
      expect(parseVerdict('{"valid": "true"}'), isNull);
      expect(parseVerdict('sure, valid'), isNull);
      expect(parseVerdict('{broken'), isNull);
    });

    GoalFetcher fetcher(int status, Object body) => GoalFetcher(MockClient((r) async => http.Response(jsonEncode(body), status)));
    final ok = fetcher(200, {'total_count': 0, 'incomplete_results': false});
    Future<ChangeResult> judge(GoalFetcher f, Future<String> Function(String, String)? ask, {String to = 'newname'}) =>
        HandleChangeJudge(f, ask).judge(source: 'github', oldHandle: 'old', newHandle: to, reason: 'I renamed my account.');

    test('allowed only on valid:true; denied carries the reason', () async {
      expect((await judge(ok, (s, u) async => '{"valid": true, "reason": "renamed"}')).outcome, ChangeOutcome.allowed);
      final d = await judge(ok, (s, u) async => '{"valid": false, "reason": "Wanting more commits."}');
      expect(d.outcome, ChangeOutcome.denied);
      expect(d.message, 'Wanting more commits.');
    });

    test('fails closed: no key, garbage, errors, unknown or same name never allow', () async {
      expect((await judge(ok, null)).outcome, ChangeOutcome.unavailable);
      expect((await judge(ok, (s, u) async => 'yes')).outcome, ChangeOutcome.unavailable);
      expect((await judge(ok, (s, u) async => throw Exception('offline'))).outcome, ChangeOutcome.unavailable);
      expect((await judge(fetcher(422, {}), (s, u) async => '{"valid": true}')).outcome, ChangeOutcome.unavailable);
      expect((await judge(ok, (s, u) async => '{"valid": true}', to: 'old')).outcome, ChangeOutcome.unavailable);
      expect((await judge(ok, (s, u) async => '{"valid": true}', to: 'bad name')).outcome, ChangeOutcome.unavailable);
    });

    test('the prompt carries both names and the reason inside tags', () async {
      String? seen;
      await judge(ok, (s, u) async {
        seen = u;
        return '{"valid": false}';
      });
      expect(seen, allOf(contains('old'), contains('newname'), contains('<reason>')));
    });

    test('store: handles stay locked, the request is kept and cleared', () async {
      final ldb = await LibraryDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final st = await GoalStore.of(ldb);
      await st.saveGoalConfig('2026-11-01', GoalConfig([Goal('github', 'old', 1), Goal('leetcode', 'lee', 1)], {'instagram'}).toJson());
      await st.saveGoalConfig('2026-11-05', GoalConfig([Goal('github', 'old', 2)], {'instagram'}).toJson());
      expect(await st.lockedHandles(), {'github': 'old', 'leetcode': 'lee'}); // leetcode stays locked though switched off
      expect(await st.changeRequestedOn(), isNull);
      await st.requestChange('2026-11-09');
      expect(await st.changeRequestedOn(), '2026-11-09');
      await st.clearChange();
      expect(await st.changeRequestedOn(), isNull);
      await ldb.close();
    });
  });
}
