import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../data/folders.dart';
import '../data/library_db.dart';
import '../native/counter_bridge.dart';
import 'apify.dart';
import 'gemini.dart';
import 'linkedin.dart';
import 'providers.dart';

/// The keys that can make notes: Gemini (several, taken in turn) for video, OpenAI and Claude from frames.
class AnalysisKeys {
  final List<String> gemini;
  final String? openai;
  final String? claude;
  const AnalysisKeys({this.gemini = const [], this.openai, this.claude});
  bool get isEmpty => gemini.isEmpty && openai == null && claude == null;
}

class _NoGemini implements Exception {}

/// What one reel being analysed needs to know apart from the others running at the same time.
class _ItemCtx {
  final int turn;
  final Job job;
  String title = '';

  /// Why the reel ended as `failed`, shown in the progress list.
  String fail = '';
  _ItemCtx(this.turn, this.job);
}

enum JobState { waiting, running, done, retry, failed, stopped }

/// One reel in the current run, for the progress list on the Library screen.
class Job {
  final int id;
  final String app;
  String label;
  JobState state = JobState.waiting;
  String stage = 'Waiting for a free key';
  double progress = 0;
  Job(this.id, this.app, this.label);

  bool get active => state == JobState.waiting || state == JobState.running;

  static String labelFor(PendingItem i) {
    final first = i.caption.trim().split('\n').first;
    if (first.isNotEmpty) {
      return first.length > 48 ? '${first.substring(0, 48)}…' : first;
    }
    if (i.app == 'photo') return 'Shared photo';
    if (i.author.isNotEmpty) return '@${i.author}';
    // Nothing known yet: say what it is and when it was shared; the name replaces this once it is fetched.
    final t = DateTime.fromMillisecondsSinceEpoch(i.createdAt);
    String two(int n) => n.toString().padLeft(2, '0');
    final kind = i.app == 'youtube' ? 'YouTube Short' : i.app == 'linkedin' ? 'LinkedIn post' : i.url.contains('/p/') ? 'Instagram post' : 'Instagram reel';
    return i.createdAt == 0 ? kind : '$kind shared ${two(t.hour)}:${two(t.minute)}';
  }
}

class _Cancelled implements Exception {}

/// What went wrong, in words for the user: the real cause, not a class name.
String describeError(Object e) {
  String fromBody(String m) {
    final j = RegExp(r'"message"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(m)?.group(1);
    return (j ?? m).replaceAll(r'\n', ' ').replaceAll(r'\"', '"').trim();
  }

  if (e is GeminiException) {
    final what = switch (e.kind) {
      GeminiFailure.badKey => 'The AI key was rejected',
      GeminiFailure.retryLater => 'The AI is busy or rate-limited',
      GeminiFailure.rejected => 'The AI refused this reel',
    };
    return '$what: ${fromBody(e.message)}';
  }
  if (e is SocketException) return 'No internet connection (${e.message}).';
  if (e is TimeoutException) return 'The request took too long and timed out.';
  if (e is http.ClientException) return 'Network error: ${e.message}';
  if (e is PlatformException) return 'The phone reported an error: ${e.message ?? e.code}';
  if (e is FileSystemException) return 'Could not read or write a file: ${e.message}';
  if (e is FormatException) return 'Got a reply it could not read: ${e.message}';
  return '$e';
}

final _ctxKey = Object();
_ItemCtx get _ctx => Zone.current[_ctxKey] as _ItemCtx;

/// Leave the item queued for the next run (network, 429/5xx, Instagram pause, bad key).
class _RetryLater implements Exception {
  final String reason;
  final bool stopAll;
  _RetryLater(this.reason, {this.stopAll = false});
}

/// Processes `pending_items` into library notes (IMPLEMENTATION §2.5). Runs on app open and in the background task.
class Runner {
  final CounterBridge bridge;
  final LibraryDb library;
  final http.Client client;
  final Future<AnalysisKeys> Function() keys;
  final Future<String?> Function() apifyKey;
  final Future<int> Function() readTurn;
  final Future<void> Function(int) saveTurn;
  final Gemini Function(String key) makeGemini;
  final Directory tempDir;
  final int Function() now;

  /// A folder both engines (the app and the background task) can see. The run writes where each reel is there and
  /// reads stop requests from it, so the open app can show and stop a run that lives in the other engine.
  final Directory? sharedDir;

  /// How long to wait before the second pass over the keys after a Gemini 429.
  final Duration rateWait;

  /// True when the last [processQueue] found another run holding the queue (the app and the background task never both work).
  bool lockBusy = false;

  /// Why the last run left items queued or failed one, for the library screen. Null when the last run was clean.
  String? lastProblem;

  /// Title of the note the current item produced, passed to Kotlin for the digest.
  bool _stop = false;

  /// The reels of the current run with where each one is; the Library screen listens to this.
  final jobs = ValueNotifier<List<Job>>(const []);
  final _jobById = <int, Job>{};
  final _cancelled = <int>{};
  final _pending = Queue<PendingItem>();

  /// Notes made by the last run, for the "note ready" notification.
  final finishedTitles = <String>[];

  late AnalysisKeys _keys;
  int _turn = 0;
  final _badKeys = <String>{};

  Runner({
    required this.bridge,
    required this.library,
    required this.client,
    required this.keys,
    required this.apifyKey,
    Future<int> Function()? readTurn,
    Future<void> Function(int)? saveTurn,
    Gemini Function(String key)? makeGemini,
    Directory? tempDir,
    int Function()? now,
    this.sharedDir,
    this.rateWait = const Duration(seconds: 12),
  }) : readTurn = readTurn ?? (() async => 0),
       saveTurn = saveTurn ?? ((_) async {}),
       makeGemini = makeGemini ?? ((k) => Gemini(client, k)),
       tempDir = tempDir ?? Directory.systemTemp,
       now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Returns how many items were finished this run.
  Future<int> processQueue() async {
    _keys = await keys();
    if (_keys.isEmpty) {
      return 0; // Items stay queued; the library asks for a key.
    }
    lockBusy = false;
    if (!await library.tryLock(now())) {
      lockBusy = true;
      lastProblem = 'Another analysis run is in progress; this one waits for it.';
      return 0;
    }
    // The lock is short (90 s) so a run killed with the app frees the queue quickly; a live run renews it.
    Future<void> heartbeat() async {
      await library.extendLock(now());
      try {
        await bridge.armWatchdog(); // pushed back each beat: it only fires if the app dies mid-run
      } on Object {
        // no native side (tests, or a failed call): the periodic task is still the fallback
      }
    }

    unawaited(heartbeat());
    final beat = Timer.periodic(const Duration(seconds: 30), (_) {
      heartbeat();
      unawaited(_writeShared());
    });
    final stops = Timer.periodic(const Duration(seconds: 2), (_) => _applyStopRequests());
    var finished = 0;
    lastProblem = null;
    finishedTitles.clear();
    _badKeys.clear();
    _turn = await readTurn();
    final tried = <int>{};
    // Reels that failed or are waiting on a retry stay listed (with their reason) until dismissed.
    _jobById.removeWhere((_, j) => j.state != JobState.failed && j.state != JobState.retry);
    _cancelled.clear();
    _ping();
    try {
      // Up to one worker per key, all pulling from one queue. The queue is re-read every second, so reels shared while
      // others are being analysed start at once on a free worker instead of waiting for the whole batch to end.
      // An item that asked to retry later is not tried again until the next run.
      _stop = false;
      final base = _turn;
      final limit = _workerCount;
      final active = <Future<void>>[];
      final known = <int>{};
      var slot = 0;
      Future<void> refill() async {
        for (final i in await bridge.pendingItems(status: 'queued')) {
          if (tried.contains(i.id) || !known.add(i.id)) continue;
          _pending.add(i);
          _jobById[i.id] = Job(i.id, i.app, Job.labelFor(i));
        }
        _ping();
      }

      while (!_stop) {
        await refill();
        while (active.length < limit && _pending.isNotEmpty) {
          late Future<void> w;
          w = _worker(base + slot++, tried).then((n) {
            finished += n;
            active.remove(w);
          });
          active.add(w);
        }
        if (active.isEmpty) break;
        await Future.any([...active, Future<void>.delayed(const Duration(seconds: 1))]);
      }
      await Future.wait(active); // a bad key stops new work; reels already running finish
    } finally {
      beat.cancel();
      stops.cancel();
      try {
        await bridge.disarmWatchdog();
      } on Object {
        // see heartbeat
      }
      if (finished > 0 || tried.isNotEmpty) await saveTurn(_turn);
      await library.unlock();
      // Finished and stopped reels are in the library or gone; only the ones still waiting on a retry stay listed.
      _jobById.removeWhere(
        (_, j) => j.state == JobState.done || j.state == JobState.stopped,
      );
      _ping();
    }
    return finished;
  }

  /// How many reels to analyse at once: one per Gemini key (at most 4), else one per other provider key.
  int get _workerCount {
    final n = _keys.gemini.isNotEmpty ? _keys.gemini.length : _others.length;
    return n.clamp(1, 4);
  }

  void _ping() {
    jobs.value = List.of(_jobById.values);
    unawaited(_writeShared());
  }

  File? _shared(String name) => sharedDir == null ? null : File('${sharedDir!.path}/$name');

  Future<void> _writeShared() async {
    final f = _shared('run_state.json');
    if (f == null) return;
    try {
      final tmp = File('${f.path}.$pid.tmp');
      await tmp.writeAsString(jsonEncode({
        'at': now(),
        'jobs': [
          for (final j in _jobById.values)
            {'id': j.id, 'app': j.app, 'label': j.label, 'state': j.state.name, 'stage': j.stage, 'progress': j.progress},
        ],
      }), flush: true);
      await tmp.rename(f.path);
    } on Object {
      // progress for the other engine is a convenience; the run itself must never fail on it
    }
  }

  /// The reels another engine is working on right now, or empty when its state is missing or stale.
  static Future<List<Job>> sharedJobs(Directory dir, int nowMs) async {
    try {
      final m = jsonDecode(await File('${dir.path}/run_state.json').readAsString()) as Map;
      if (nowMs - (m['at'] as int) > 150000) return const [];
      return [
        for (final j in m['jobs'] as List)
          Job(j['id'] as int, '${j['app']}', '${j['label']}')
            ..state = JobState.values.byName('${j['state']}')
            ..stage = '${j['stage']}'
            ..progress = (j['progress'] as num).toDouble(),
      ];
    } on Object {
      return const [];
    }
  }

  /// Asks whichever engine is running to stop this reel.
  static Future<void> requestStop(Directory dir, int id) async {
    final f = File('${dir.path}/run_stop.txt');
    await f.writeAsString('$id\n', mode: FileMode.append, flush: true);
  }

  Future<void> _applyStopRequests() async {
    final f = _shared('run_stop.txt');
    if (f == null || !await f.exists()) return;
    try {
      final ids = (await f.readAsString()).split('\n').map(int.tryParse).whereType<int>().toList();
      await f.delete();
      for (final id in ids) {
        await cancel(id);
      }
    } on Object {
      // read again on the next tick
    }
  }

  /// Stops one reel: a waiting one is taken off the queue, a running one stops at its next step (its AI request,
  /// if already sent, is simply ignored), and one that is waiting for a retry is dropped. The reel is not analysed.
  Future<void> cancel(int id) async {
    final job = _jobById[id];
    if (job == null ||
        job.state == JobState.done ||
        job.state == JobState.stopped) {
      return;
    }
    if (job.state == JobState.failed) {
      _jobById.remove(id); // dismissed from the list; the reel itself stays marked failed
      _ping();
      return;
    }
    if (job.state == JobState.running) {
      _cancelled.add(id);
      job.stage = 'Stopping…';
      _ping();
      return;
    }
    _pending.removeWhere((i) => i.id == id);
    job.state = JobState.stopped;
    job.stage = 'Stopped';
    await bridge.setPendingStatus(id, 'cancelled');
    _ping();
  }

  /// Waits for a slow network step but gives up the moment this reel is stopped; the abandoned request's own
  /// result or error is ignored.
  Future<T> _stoppable<T>(Future<T> work) {
    final id = _ctx.job.id;
    final out = Completer<T>();
    final poll = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_cancelled.contains(id) && !out.isCompleted) out.completeError(_Cancelled());
    });
    work.then((v) {
      if (!out.isCompleted) out.complete(v);
    }, onError: (Object e, StackTrace st) {
      if (!out.isCompleted) out.completeError(e, st);
    });
    return out.future.whenComplete(poll.cancel);
  }

  /// Records where the current reel is, and stops it here if the user asked to.
  void _step(String stage, double progress) {
    final job = _ctx.job;
    if (_cancelled.contains(job.id)) throw _Cancelled();
    job.stage = stage;
    job.progress = progress;
    _ping();
  }

  /// Takes reels off the queue until it is empty or the run must stop; returns how many it finished.
  Future<int> _worker(int turn, Set<int> tried) async {
    var done = 0;
    while (!_stop && _pending.isNotEmpty) {
      final item = _pending.removeFirst();
      tried.add(item.id);
      await library.extendLock(
        now(),
      ); // a long queue must not let the background task start a second run
      _turn++;
      final job = _jobById[item.id]!;
      final ctx = _ItemCtx(turn, job);
      job.state = JobState.running;
      job.stage = 'Starting';
      job.progress = 0.05;
      _ping();
      try {
        // The zone gives each reel its own key turn and title while workers run side by side.
        final status = await runZoned(
          () => _process(item),
          zoneValues: {_ctxKey: ctx},
        );
        await bridge.setPendingStatus(item.id, status, title: ctx.title);
        if (status == 'failed') {
          lastProblem = 'Failed: ${ctx.fail}';
          job
            ..state = JobState.failed
            ..stage = ctx.fail;
        } else {
          if (ctx.title.isNotEmpty) finishedTitles.add(ctx.title);
          job
            ..state = JobState.done
            ..stage = ctx.title.isEmpty ? 'Done' : 'Done: ${ctx.title}'
            ..progress = 1;
          done++;
        }
      } on _Cancelled {
        await bridge.setPendingStatus(item.id, 'cancelled');
        job
          ..state = JobState.stopped
          ..stage = 'Stopped';
      } on _RetryLater catch (e) {
        lastProblem = 'Will retry: ${e.reason}';
        job
          ..state = JobState.retry
          ..stage = 'Will retry: ${e.reason}';
        if (e.stopAll) _stop = true;
      } catch (e) {
        // Errors too, not just Exceptions: an uncaught one used to leave the item queued with no reason shown.
        final why = describeError(e);
        lastProblem = 'Failed: $why';
        await bridge.setPendingStatus(item.id, 'failed');
        job
          ..state = JobState.failed
          ..stage = why;
      }
      _ping();
    }
    return done;
  }

  /// Runs [f] with this reel's Gemini key; on a rate limit or a bad key, the next key gets a go.
  Future<T> _gemini<T>(Future<T> Function(Gemini g) f) async {
    final ks = _keys.gemini;
    GeminiException? last;
    // Two passes: if every key is rate limited, wait a moment (the free tier counts requests per minute)
    // and try once more before leaving the reel for the next run.
    for (var pass = 0; pass < 2; pass++) {
      var limited = false;
      for (var i = 0; i < ks.length; i++) {
        final k = ks[(_ctx.turn + i) % ks.length];
        if (_badKeys.contains(k)) continue;
        try {
          _step(
            'Analysing with Gemini${ks.length > 1 ? ' key ${ks.indexOf(k) + 1}' : ''}',
            0.55,
          );
          return await _stoppable(f(makeGemini(k)));
        } on GeminiException catch (e) {
          if (e.kind == GeminiFailure.rejected) rethrow;
          if (e.kind == GeminiFailure.badKey) _badKeys.add(k);
          if (e.kind == GeminiFailure.retryLater &&
              e.message.contains('HTTP 429')) {
            limited = true;
          }
          last = e;
        }
      }
      if (!limited || pass == 1) break;
      await Future<void>.delayed(rateWait);
    }
    throw last ?? _NoGemini();
  }

  List<ChatModel> get _others => [
    if (_keys.openai != null) ChatModel('openai', _keys.openai!, client),
    if (_keys.claude != null) ChatModel('claude', _keys.claude!, client),
  ];

  /// OpenAI / Claude, in that order, for when Gemini can't (no key, all keys limited).
  Future<Analysis> _viaOthers(
    String context,
    List<List<int>> images,
    Object? geminiError,
  ) async {
    Object? last = geminiError;
    for (final m in _others) {
      try {
        _step('Analysing with ${m.label}', 0.55);
        return await _stoppable(m.analyse(context, images));
      } on GeminiException catch (e) {
        if (e.kind == GeminiFailure.rejected) rethrow;
        last = e;
      }
    }
    if (last is GeminiException) throw last;
    throw GeminiException(
      GeminiFailure.retryLater,
      'no provider could take this reel',
    );
  }

  Future<Analysis> _video(File f, String context) async {
    Object? err;
    try {
      return await _gemini((g) => g.video(f, context: context));
    } on _NoGemini {
      // fall through to frames
    } on GeminiException catch (e) {
      if (e.kind == GeminiFailure.rejected || _others.isEmpty) rethrow;
      err = e;
    }
    // ponytail: 6 frames, no audio; Gemini stays the only provider that hears the reel.
    return _viaOthers(context, await bridge.videoFrames(f.path), err);
  }

  Future<Analysis> _captionAndThumbnail(String text, List<int>? jpeg) async {
    Object? err;
    try {
      return await _gemini(
        (g) => g.captionAndThumbnail(text: text, jpeg: jpeg),
      );
    } on _NoGemini {
      // fall through
    } on GeminiException catch (e) {
      if (e.kind == GeminiFailure.rejected || _others.isEmpty) rethrow;
      err = e;
    }
    return _viaOthers(
      'Caption and thumbnail only (no video available).\n$text',
      [?jpeg],
      err,
    );
  }

  String _failed(String why) {
    _ctx.fail = why;
    return 'failed';
  }

  /// Names the reel in the progress list once something better than its link is known.
  void _name(String? text) {
    final first = (text ?? '').trim().split('\n').first.trim();
    if (first.isEmpty) return;
    _ctx.job.label = first.length > 48 ? '${first.substring(0, 48)}…' : first;
    _ping();
  }

  Future<String> _process(PendingItem item) async {
    if (item.url.isEmpty) {
      return item.author.isEmpty &&
              item.caption.isEmpty &&
              item.onScreenText.isEmpty
          ? _failed('The share had no link, author or caption to work from.')
          : await _textOnly(item);
    }
    if (await library.has(item.url)) {
      // Shared again: don't spend tokens on it twice; bring the note back to the top, unread.
      await library.resurface(item.url, now());
      return 'done';
    }
    try {
      return switch (item.app) {
        'youtube' => await _youtube(item),
        'photo' => await _photo(item),
        'linkedin' => await _linkedin(item),
        _ => await _instagram(item),
      };
    } on GeminiException catch (e) {
      if (e.kind == GeminiFailure.badKey) {
        throw _RetryLater(
          'Your key was rejected (${e.message.split(':').first}). Check it in Settings.',
          stopAll: true,
        );
      }
      if (e.kind == GeminiFailure.retryLater) throw _RetryLater(e.toString());
      rethrow;
    } on RateLimited catch (e) {
      throw _RetryLater(
        e.loginWall
            ? 'Instagram wants a login to show this post (often a private account). Reel Analyser tries again in a few minutes, '
                  'up to 3 times, then makes the note from what it has.'
            : 'Instagram is limiting requests right now. Reel Analyser retries on its own in a few minutes.',
      );
    } on TimeoutException {
      throw _RetryLater('the site did not answer in time');
    } on SocketException catch (e) {
      throw _RetryLater('no network ($e)');
    } on http.ClientException catch (e) {
      throw _RetryLater('network error ($e)');
    }
  }

  /// v0.8: shared photos. The image stays in app storage, so the note can show it.
  Future<String> _photo(PendingItem item) async {
    final f = File(item.url.substring('photo:'.length));
    if (!await f.exists()) return _failed('The shared photo file is missing; it may have been deleted.');
    final context = item.caption.isEmpty ? '' : 'Shared with: ${item.caption}';
    await _save(
      item,
      await _pictures([await f.readAsBytes()], context),
      'done',
      0,
      caption: item.caption,
    );
    return 'done';
  }

  /// Gemini for pictures, else OpenAI / Claude (they take images too).
  Future<Analysis> _pictures(List<List<int>> jpegs, String context) async {
    Object? err;
    try {
      return await _gemini((g) => g.images(jpegs, context: context));
    } on _NoGemini {
      // fall through
    } on GeminiException catch (e) {
      if (e.kind == GeminiFailure.rejected || _others.isEmpty) rethrow;
      err = e;
    }
    return _viaOthers(
      'Pictures, not a video (${jpegs.length}). $context',
      jpegs,
      err,
    );
  }

  /// LinkedIn: the public post page (no login) gives the text, author, pictures and, for a video, the mp4. The video is
  /// watched like a reel; otherwise the pictures, otherwise the text alone. The page and the video are not kept.
  Future<String> _linkedin(PendingItem item) async {
    final u = Uri.parse(item.url);
    if (!isLinkedInHost(u.host)) return _failed('Not a LinkedIn link.');
    _step('Fetching from LinkedIn', 0.12);
    final r = await _stoppable(client.get(u, headers: {'User-Agent': linkedInUserAgent, 'Accept-Language': 'en-US,en;q=0.9'}))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode == 429 || r.statusCode >= 500) throw GeminiException(GeminiFailure.retryLater, 'LinkedIn is busy (HTTP ${r.statusCode})');
    final p = r.statusCode == 200 ? parseLinkedIn(utf8.decode(r.bodyBytes, allowMalformed: true)) : const LinkedInPost();
    if (p.isEmpty) {
      return _failed('LinkedIn did not show this post without a login (HTTP ${r.statusCode}). Only public posts can be read.');
    }
    _step(p.videoUrl.isNotEmpty ? 'Got the video' : 'Got the post', 0.35);
    _name(p.text.isNotEmpty ? p.text : p.author);
    final context = [
      'LinkedIn post',
      if (p.author.isNotEmpty) 'Author: ${p.author}',
      if (p.text.isNotEmpty) 'Post text: ${p.text}',
    ].join('\n');
    final caption = p.text.length > 2000 ? p.text.substring(0, 2000) : p.text;
    if (p.videoUrl.isNotEmpty) {
      final path = await _download(p.videoUrl, '${item.id}', referer: 'https://www.linkedin.com/', prefix: 'linkedin');
      if (path != null) {
        final file = File(path);
        try {
          await _save(item, await _video(file, context), 'done', 0, author: p.author, caption: caption);
          return 'done';
        } on GeminiException catch (e) {
          if (e.kind != GeminiFailure.rejected) rethrow;
        } finally {
          if (await file.exists()) await file.delete();
        }
      }
    }
    final pics = [for (final i in p.images) ?await _bytes(i)];
    if (pics.isNotEmpty) {
      await _save(item, await _pictures(pics, context), 'done', 0, author: p.author, caption: caption);
      return 'done';
    }
    final a = await _captionAndThumbnail(context, p.thumbnail.isEmpty ? null : await _bytes(p.thumbnail));
    await _save(item, a, p.thumbnail.isEmpty ? 'text-only' : 'caption+thumbnail', 0, author: p.author, caption: caption);
    return p.thumbnail.isEmpty ? 'text-only' : 'caption+thumbnail';
  }

  Future<String> _youtube(PendingItem item) async {
    final ctx = _ctx;
    // Just for the progress list: the video's title, fetched while Gemini works.
    unawaited(client
        .get(Uri.parse('https://www.youtube.com/oembed?url=${Uri.encodeComponent(item.url)}&format=json'))
        .timeout(const Duration(seconds: 8))
        .then((r) {
      if (r.statusCode != 200 || ctx.title.isNotEmpty) return;
      final t = '${(jsonDecode(utf8.decode(r.bodyBytes)) as Map)['title'] ?? ''}'.trim();
      if (t.isNotEmpty && !_cancelled.contains(ctx.job.id)) {
        ctx.job.label = t.length > 48 ? '${t.substring(0, 48)}…' : t;
        _ping();
      }
    }).catchError((_) {}));
    try {
      await _save(item, await _gemini((g) => g.youtube(item.url)), 'done', 0);
      return 'done';
    } on _NoGemini {
      // only Gemini can watch a YouTube link; the others get the title and thumbnail
    } on GeminiException catch (e) {
      if (e.kind != GeminiFailure.rejected) {
        rethrow; // limited: wait for Gemini rather than settle for a thumbnail
      }
    }
    // YT-OEMBED: Gemini refused the URL (private, unlisted, or the free daily cap).
    final r = await client.get(
      Uri.parse(
        'https://www.youtube.com/oembed?url=${Uri.encodeComponent(item.url)}&format=json',
      ),
    );
    if (r.statusCode != 200) return _failed('YouTube would not describe this video (HTTP ${r.statusCode}); it may be private or removed.');
    final o = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final author = '${o['author_name'] ?? ''}';
    final a = await _captionAndThumbnail(
      'Channel: $author\nTitle: ${o['title'] ?? ''}',
      await _bytes('${o['thumbnail_url'] ?? ''}'),
    );
    await _save(
      item,
      a,
      'caption+thumbnail',
      0,
      author: author,
      caption: '${o['title'] ?? ''}',
    );
    return 'caption+thumbnail';
  }

  Future<String> _instagram(PendingItem item) async {
    IgFetch f;
    _step('Fetching from Instagram', 0.12);
    try {
      f = await _stoppable(bridge.fetchInstagram(item.url));
    } on PlatformException {
      f = const IgFetch();
    }
    _step(f.videoPath != null ? 'Got the video' : 'Got the post details', 0.35);
    _name(f.caption.isNotEmpty ? f.caption : f.author.isNotEmpty ? '@${f.author}' : null);
    var author = f.author.isEmpty ? item.author : f.author;
    var caption = f.caption.isEmpty ? item.caption : f.caption;
    var thumb = f.thumbnailUrl;
    var step = f.step;
    var videoPath = f.videoPath;

    final apify = videoPath == null ? await apifyKey() : null;
    final code = RegExp(r'instagram\.com/(?:reel|reels|p|tv)/([A-Za-z0-9_-]+)')
        .firstMatch(item.url)
        ?.group(1);
    if (apify != null && code != null) {
      ApifyResult? a;
      try {
        a = await apifyFetch(client, apify, code);
      } on Exception {
        a = null; // bad key, no credit or timeout: carry on with what the cascade found
      }
      if (a != null) {
        if (author.isEmpty) author = a.author;
        if (caption.isEmpty) caption = a.caption;
        if (thumb.isEmpty) thumb = a.thumbnailUrl;
        if (a.videoUrl.isNotEmpty) {
          videoPath = await _download(a.videoUrl, code);
        }
        if (videoPath != null || step == 0) {
          step = 7; // Apify, after the six Kotlin steps
        }
      }
    }

    final context = [
      if (author.isNotEmpty) 'Author: @$author',
      if (caption.isNotEmpty) 'Caption: $caption',
      if (item.onScreenText.isNotEmpty) 'On screen: ${item.onScreenText}',
    ].join('\n');

    if (videoPath != null) {
      final file = File(videoPath);
      try {
        await _save(
          item,
          await _video(file, context),
          'done',
          step,
          author: author,
          caption: caption,
        );
        return 'done';
      } on GeminiException catch (e) {
        if (e.kind != GeminiFailure.rejected) rethrow;
      } finally {
        if (await file.exists()) await file.delete(); // only text is kept
      }
    }
    // v0.8: a photo post or carousel: every picture, so the note covers the whole post, not just its cover.
    if (videoPath == null && f.images.isNotEmpty) {
      final pics = [for (final u in f.images.take(10)) ?await _bytes(u)];
      if (pics.isNotEmpty) {
        await _save(
          item,
          await _pictures(pics, context),
          'done',
          step,
          author: author,
          caption: caption,
        );
        return 'done';
      }
    }
    if (caption.isNotEmpty || thumb.isNotEmpty) {
      final a = await _captionAndThumbnail(context, await _bytes(thumb));
      await _save(
        item,
        a,
        'caption+thumbnail',
        step,
        author: author,
        caption: caption,
      );
      return 'caption+thumbnail';
    }
    if (author.isNotEmpty || item.onScreenText.isNotEmpty) {
      return _textOnly(item, author: author, step: step);
    }
    return _failed('Instagram gave nothing for this link: no video, picture, caption or author. It may be private or deleted.');
  }

  /// Instagram posts where only the author could be found (and URL-less rows from before v0.9.0).
  Future<String> _textOnly(
    PendingItem item, {
    String? author,
    int step = 0,
  }) async {
    final who = author ?? item.author;
    final a = await _captionAndThumbnail(
      'Author: @$who\nCaption: ${item.caption}\nOn screen: ${item.onScreenText}',
      null,
    );
    await _save(item, a, 'text-only', step, author: who, caption: item.caption);
    return 'text-only';
  }

  Future<void> _save(
    PendingItem item,
    Analysis a,
    String analysis,
    int step, {
    String author = '',
    String caption = '',
  }) async {
    _step('Saving the note', 0.95);
    _name(a.title);
    final saved = Reel(
        url: item.url.isEmpty ? 'local:${item.id}' : item.url,
        app: item.app,
        title: _ctx.title = a.title.isEmpty
            ? (caption.isEmpty ? 'Untitled reel' : caption.split('\n').first)
            : a.title,
        summary: a.summary,
        keyPoints: a.keyPoints,
        tags: a.tags,
        overview: a.overview,
        mentions: a.mentions,
        author: author,
        caption: caption,
        transcript: a.transcript,
        onScreenText: [
          a.onScreenText,
          if (a.onScreenText.isEmpty) item.onScreenText,
        ].where((e) => e.isNotEmpty).join('\n'),
        analysis: analysis,
        step: step,
        savedAt: item.createdAt == 0 ? now() : item.createdAt,
      );
    await library.saveReel(saved);
    await _sortIntoFolder(saved);
  }

  /// A new note goes into the folder its words clearly match (no AI call). A note already in a folder keeps it.
  Future<void> _sortIntoFolder(Reel r) async {
    final folders = await library.folders();
    if (folders.isEmpty || (await library.folderOf()).containsKey(r.url)) return;
    final f = matchFolder(r, folders);
    if (f != null) await library.setFolders({r.url: f});
  }

  Future<List<int>?> _bytes(String url) async {
    if (url.isEmpty) return null;
    try {
      final r = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      return r.statusCode == 200 ? r.bodyBytes : null;
    } on Exception {
      return null;
    }
  }

  /// Apify's video link, downloaded now (CDN links expire). 100 MB cap, as in IG-CDN.
  Future<String?> _download(String url, String code, {String referer = 'https://www.instagram.com/', String prefix = 'apify'}) async {
    final f = File('${tempDir.path}/$prefix-$code.mp4');
    try {
      final r = await client.send(
        http.Request('GET', Uri.parse(url))
          ..headers['Referer'] = referer,
      );
      if (r.statusCode != 200) return null;
      final sink = f.openWrite();
      var total = 0;
      await for (final chunk in r.stream) {
        total += chunk.length;
        if (total > 100 * 1024 * 1024) {
          await sink.close();
          await f.delete();
          return null;
        }
        sink.add(chunk);
      }
      await sink.close();
      return f.path;
    } on Exception {
      return null;
    }
  }
}
