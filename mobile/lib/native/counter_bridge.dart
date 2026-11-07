import 'package:flutter/services.dart';

/// A row of `pending_items` in Kotlin's `counter.db` (CH-COUNTER).
class PendingItem {
  final int id;
  final String url;
  final String app;
  final String author;
  final String caption;
  final String onScreenText;
  final int createdAt;
  final String status;

  const PendingItem({
    required this.id,
    required this.url,
    required this.app,
    this.author = '',
    this.caption = '',
    this.onScreenText = '',
    this.createdAt = 0,
    this.status = 'queued',
  });

  factory PendingItem.fromMap(Map m) => PendingItem(
        id: (m['id'] as num).toInt(),
        url: m['url'] as String? ?? '',
        app: m['app'] as String? ?? '',
        author: m['author'] as String? ?? '',
        caption: m['caption'] as String? ?? '',
        onScreenText: m['onScreenText'] as String? ?? '',
        createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
        status: m['status'] as String? ?? 'queued',
      );
}

/// What Kotlin's Instagram cascade found. `step` is the PLAN §3.2 step (0 = nothing).
class IgFetch {
  final int step;
  final String author;
  final String caption;
  final String thumbnailUrl;
  final String? videoPath;

  /// Every picture of a photo post or carousel (up to 10).
  final List<String> images;

  const IgFetch({this.step = 0, this.author = '', this.caption = '', this.thumbnailUrl = '', this.videoPath, this.images = const []});

  factory IgFetch.fromMap(Map m) => IgFetch(
        step: (m['step'] as num?)?.toInt() ?? 0,
        author: m['author'] as String? ?? '',
        caption: m['caption'] as String? ?? '',
        thumbnailUrl: m['thumbnailUrl'] as String? ?? '',
        videoPath: m['videoPath'] as String?,
        images: [for (final u in m['images'] as List? ?? const []) '$u'],
      );
}

/// Instagram is pausing us (429 / login wall); the item stays queued. [reason] is Kotlin's message.
class RateLimited implements Exception {
  final String reason;
  RateLimited([this.reason = '']);

  /// Every step for this post hit a login wall: usually a private account's post, not a rate limit.
  bool get loginWall => reason.contains('login wall');

  @override
  String toString() => 'Instagram is rate-limiting; will retry later';
}

/// One row of Kotlin's `daily_counts` view.
class DayCount {
  final String date;
  final String app;
  final int reels;
  final int ms;
  final int unknown;
  const DayCount(this.date, this.app, {this.reels = 0, this.ms = 0, this.unknown = 0});

  factory DayCount.fromMap(Map m) => DayCount(m['date'] as String, m['app'] as String,
      reels: (m['reels'] as num).toInt(), ms: (m['ms'] as num).toInt(), unknown: (m['unknown'] as num).toInt());
}

/// A day's rows summed over both apps.
class DayTotal {
  final String date;
  final Map<String, int> reelsByApp;

  /// Time on the Reels and Shorts screens, from the optional Accessibility counter.
  final int ms;
  final int unknown;

  /// Time in each whole app (Instagram, YouTube), from Usage access.
  final Map<String, int> appMs;
  const DayTotal(this.date, this.reelsByApp, this.ms, this.unknown, {this.appMs = const {}});

  int get reels => reelsByApp.values.fold(0, (a, b) => a + b);

  /// The time to show: time in the apps when Usage access gives it, else the counter's Reels/Shorts time.
  int get timeMs => appMs.isEmpty ? ms : appMs.values.fold(0, (a, b) => a + b);

  DayTotal withAppMs(Map<String, int> m) => DayTotal(date, reelsByApp, ms, unknown, appMs: m);

  /// Same rule as the Kotlin alert: at least 5 unreadable and 30% of what was seen.
  bool get detectionLooksBroken => unknown >= 5 && unknown * 10 >= (reels + unknown) * 3;

  /// Groups `daily` rows by date, keeping their newest-first order.
  static List<DayTotal> group(List<DayCount> rows) {
    final out = <String, DayTotal>{};
    for (final r in rows) {
      final t = out[r.date];
      out[r.date] = DayTotal(r.date, {...?t?.reelsByApp, r.app: r.reels}, (t?.ms ?? 0) + r.ms, (t?.unknown ?? 0) + r.unknown);
    }
    return out.values.toList();
  }
}

class SeenItem {
  final String app;
  final String fp;
  final int firstSeen;
  final int dwellMs;
  final String author;
  final String caption;
  const SeenItem(this.app, this.fp, this.firstSeen, this.dwellMs, this.author, this.caption);

  factory SeenItem.fromMap(Map m) => SeenItem(m['app'] as String, m['fp'] as String, (m['firstSeen'] as num).toInt(),
      (m['dwellMs'] as num).toInt(), m['author'] as String? ?? '', m['caption'] as String? ?? '');
}

class CounterStatus {
  final bool serviceEnabled;
  final bool serviceRunning;
  final bool batteryExempt;
  final bool notificationsAllowed;
  final int sdkInt;
  final String manufacturer;
  final bool capture;

  /// Usage access: time in Instagram and YouTube. The Accessibility counter (reel counts) is optional on top.
  final bool usageAccess;

  CounterStatus.fromMap(Map m)
      : serviceEnabled = m['serviceEnabled'] == true,
        serviceRunning = m['serviceRunning'] == true,
        batteryExempt = m['batteryExempt'] == true,
        notificationsAllowed = m['notificationsAllowed'] == true,
        sdkInt = (m['sdkInt'] as num?)?.toInt() ?? 0,
        manufacturer = m['manufacturer'] as String? ?? '',
        capture = m['capture'] == true,
        usageAccess = m['usageAccess'] == true;

  /// Phones whose battery managers kill background services unless Autostart is allowed.
  bool get needsAutostart => const ['xiaomi', 'redmi', 'poco', 'oppo', 'realme', 'oneplus', 'vivo', 'iqoo', 'huawei', 'honor']
      .contains(manufacturer.toLowerCase());
}

/// The phone's local date as Kotlin writes it, `yyyy-MM-dd`.
String localDate([DateTime? t]) => (t ?? DateTime.now()).toIso8601String().substring(0, 10);

class CounterBridge {
  static const _ch = MethodChannel('reelbot/counter');

  Future<List<PendingItem>> pendingItems({String? status}) async {
    final rows = await _ch.invokeListMethod<Map>('pendingItems', {'status': status}) ?? [];
    return rows.map(PendingItem.fromMap).toList();
  }

  /// `title` is the analysed note's title, which the Kotlin digest shows (WM-DIGEST).
  Future<void> setPendingStatus(int id, String status, {String title = ''}) =>
      _ch.invokeMethod('setPendingStatus', {'id': id, 'status': status, 'title': title});

  /// Evenly spaced JPEG frames of a downloaded video, for OpenAI / Claude, which take images but not video.
  Future<List<List<int>>> videoFrames(String path, {int count = 6}) async =>
      (await _ch.invokeListMethod<Uint8List>('videoFrames', {'path': path, 'count': count}) ?? []).toList();

  /// Opens a web page in the browser (feedback goes to the project's GitHub issues this way).
  Future<void> openUrl(String url) => _ch.invokeMethod('openUrl', {'url': url});

  /// "Note ready" notification after a background run; tapping it opens the app.
  Future<void> notifyNotes(String title, String text) => _ch.invokeMethod('notifyNotes', {'title': title, 'text': text});

  /// Deletes files in the app's photo folder that aren't in [keep].
  Future<void> sweepPhotos(List<String> keep) => _ch.invokeMethod('sweepPhotos', {'keep': keep});

  /// The digest is skipped on days the app was opened. Also applies the retention rules (old Insights data goes).
  Future<void> markOpened() => _ch.invokeMethod('markOpened');

  /// "Erase all my data": counters, queue, debug rows, shared photos and the notification state.
  Future<void> eraseAll() => _ch.invokeMethod('eraseAll');

  Future<IgFetch> fetchInstagram(String url) async {
    try {
      return IgFetch.fromMap((await _ch.invokeMapMethod('fetchInstagram', {'url': url}))!);
    } on PlatformException catch (e) {
      if (e.code == 'rate_limited') throw RateLimited(e.message ?? '');
      rethrow;
    }
  }

  Future<void> saveDownload(String name, String text) =>
      _ch.invokeMethod('saveDownload', {'name': name, 'text': text});

  /// Counter rows per day, with time in each app from Usage access merged in; newest first.
  Future<List<DayTotal>> history({int days = 14}) async {
    final rows = await _ch.invokeListMethod<Map>('daily', {'days': days}) ?? [];
    return mergeAppTime(DayTotal.group(rows.map(DayCount.fromMap).toList()), (await _appUsage(days))['daily']!);
  }

  /// Reels and time per hour of the day (0–23) over the last [days] days; hours with nothing are 0.
  /// Time is time in the apps when Usage access is on, else the counter's Reels/Shorts time.
  Future<List<(int reels, int ms)>> hourly({int days = 7}) async {
    final out = List.filled(24, (0, 0));
    for (final r in await _ch.invokeListMethod<Map>('hourly', {'days': days}) ?? []) {
      out[(r['hour'] as num).toInt()] = ((r['reels'] as num).toInt(), (r['ms'] as num?)?.toInt() ?? 0);
    }
    final app = (await _appUsage(days))['hourly']!;
    if (app.isEmpty) return out;
    final byHour = List.filled(24, 0);
    for (final r in app) {
      byHour[(r['hour'] as num).toInt()] += (r['ms'] as num).toInt();
    }
    return [for (var h = 0; h < 24; h++) (out[h].$1, byHour[h])];
  }

  (int, DateTime, Future<Map<String, dynamic>?>)? _usage;

  /// `daily` and `hourly` rows of time per app; both empty without Usage access. [history] and [hourly] are
  /// called together every few seconds, so one read of Android's usage events serves both for 2 s.
  Future<Map<String, List<Map>>> _appUsage(int days) async {
    final u = _usage;
    final fresh = u != null && u.$1 == days && DateTime.now().difference(u.$2) < const Duration(seconds: 2);
    final pending = fresh ? u.$3 : _ch.invokeMapMethod<String, dynamic>('appUsage', {'days': days});
    if (!fresh) _usage = (days, DateTime.now(), pending);
    final m = await pending ?? const {};
    return {
      'daily': [for (final r in m['daily'] as List? ?? const []) r as Map],
      'hourly': [for (final r in m['hourly'] as List? ?? const []) r as Map],
    };
  }

  Future<List<SeenItem>> seenItems(String date) async =>
      (await _ch.invokeListMethod<Map>('seenItems', {'date': date}) ?? []).map(SeenItem.fromMap).toList();

  /// `debug_state` as key → value.
  Future<Map<String, String>> debugState() async =>
      {for (final r in await _ch.invokeListMethod<Map>('debugState') ?? []) r['k'] as String: r['v'] as String};

  Future<void> setCapture(bool on) => _ch.invokeMethod('setCapture', {'on': on});


  Future<CounterStatus> status() async => CounterStatus.fromMap((await _ch.invokeMapMethod('status'))!);

  /// Opens a system screen: `openUsageAccess`, `openAccessibilitySettings`, `openAppInfo`, `openNotificationSettings`,
  /// `requestBatteryExemption` or `openAutostart`.
  Future<void> open(String screen) => _ch.invokeMethod(screen);
}

/// Adds Usage-access time (`{date, app, ms}` rows) to the counter's days; dates only one side has are kept. Newest first.
List<DayTotal> mergeAppTime(List<DayTotal> days, List<Map> appRows) {
  final app = <String, Map<String, int>>{};
  for (final r in appRows) {
    (app[r['date'] as String] ??= {})[r['app'] as String] = (r['ms'] as num).toInt();
  }
  final byDate = {for (final d in days) d.date: d};
  for (final date in app.keys) {
    byDate[date] = (byDate[date] ?? DayTotal(date, const {}, 0, 0)).withAppMs(app[date]!);
  }
  return byDate.values.toList()..sort((a, b) => b.date.compareTo(a.date));
}
