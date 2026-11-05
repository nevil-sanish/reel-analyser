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

  const IgFetch({this.step = 0, this.author = '', this.caption = '', this.thumbnailUrl = '', this.videoPath});

  factory IgFetch.fromMap(Map m) => IgFetch(
        step: (m['step'] as num?)?.toInt() ?? 0,
        author: m['author'] as String? ?? '',
        caption: m['caption'] as String? ?? '',
        thumbnailUrl: m['thumbnailUrl'] as String? ?? '',
        videoPath: m['videoPath'] as String?,
      );
}

/// Instagram is pausing us (429 / login wall); the item stays queued.
class RateLimited implements Exception {
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
  final int ms;
  final int unknown;
  const DayTotal(this.date, this.reelsByApp, this.ms, this.unknown);

  int get reels => reelsByApp.values.fold(0, (a, b) => a + b);

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

  CounterStatus.fromMap(Map m)
      : serviceEnabled = m['serviceEnabled'] == true,
        serviceRunning = m['serviceRunning'] == true,
        batteryExempt = m['batteryExempt'] == true,
        notificationsAllowed = m['notificationsAllowed'] == true,
        sdkInt = (m['sdkInt'] as num?)?.toInt() ?? 0,
        manufacturer = m['manufacturer'] as String? ?? '',
        capture = m['capture'] == true;

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

  Future<void> setPendingStatus(int id, String status) =>
      _ch.invokeMethod('setPendingStatus', {'id': id, 'status': status});

  Future<IgFetch> fetchInstagram(String url) async {
    try {
      return IgFetch.fromMap((await _ch.invokeMapMethod('fetchInstagram', {'url': url}))!);
    } on PlatformException catch (e) {
      if (e.code == 'rate_limited') throw RateLimited();
      rethrow;
    }
  }

  Future<void> saveDownload(String name, String text) =>
      _ch.invokeMethod('saveDownload', {'name': name, 'text': text});

  Future<List<DayTotal>> history({int days = 14}) async {
    final rows = await _ch.invokeListMethod<Map>('daily', {'days': days}) ?? [];
    return DayTotal.group(rows.map(DayCount.fromMap).toList());
  }

  Future<List<SeenItem>> seenItems(String date) async =>
      (await _ch.invokeListMethod<Map>('seenItems', {'date': date}) ?? []).map(SeenItem.fromMap).toList();

  /// `debug_state` as key → value.
  Future<Map<String, String>> debugState() async =>
      {for (final r in await _ch.invokeListMethod<Map>('debugState') ?? []) r['k'] as String: r['v'] as String};

  Future<void> setCapture(bool on) => _ch.invokeMethod('setCapture', {'on': on});

  Future<CounterStatus> status() async => CounterStatus.fromMap((await _ch.invokeMapMethod('status'))!);

  /// Opens a system screen: `openAccessibilitySettings`, `openAppInfo`, `openNotificationSettings`,
  /// `requestBatteryExemption` or `openAutostart`.
  Future<void> open(String screen) => _ch.invokeMethod(screen);
}
