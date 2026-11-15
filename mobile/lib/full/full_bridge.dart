import 'package:flutter/services.dart';

// The part of the native channel that only the full build has: the reel counter, Usage access, notifications, the in-app
// update installer and the system-screen shortcuts. The semi build has no native code behind any of it, and does not compile this file.

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


/// The full build's side of the `reelbot/counter` channel.
class FullBridge {
  static const _ch = MethodChannel('reelbot/counter');

  /// "Note ready" notification after a background run; tapping it opens the app.
  Future<void> notifyNotes(String title, String text) => _ch.invokeMethod('notifyNotes', {'title': title, 'text': text});

  /// The digest is skipped on days the app was opened. Also applies the retention rules (old Insights data goes).
  Future<void> markOpened() => _ch.invokeMethod('markOpened');

  /// The app's own folder for a downloaded update.
  Future<String> updateDir() async => (await _ch.invokeMethod<String>('updateDir'))!;

  /// Opens Android's installer on a downloaded update: `started`, `needs_permission` (the settings screen was opened) or `failed: <reason>`.
  Future<String> installApk(String path) async => await _ch.invokeMethod<String>('installApk', {'path': path}) ?? 'failed';

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
