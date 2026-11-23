import 'dart:convert';

import 'package:flutter/services.dart';

/// One app (`kind` app, `id` the package) or website (`kind` site, `id` the host) with its daily time in minutes.
class LimitItem {
  final String kind;
  final String id;
  final String label;
  final int limitMin;
  const LimitItem(this.kind, this.id, this.label, this.limitMin);

  String get key => '$kind:$id';
  bool get isSite => kind == 'site';
  LimitItem withLimit(int m) => LimitItem(kind, id, label, m);

  Map<String, Object> toMap() => {'kind': kind, 'id': id, 'label': label, 'limitMin': limitMin};

  static List<LimitItem> parse(String? json) {
    if (json == null) return const [];
    try {
      return [
        for (final o in jsonDecode(json) as List)
          LimitItem('${o['kind']}', '${o['id']}', '${o['label']}', (o['limitMin'] as num).toInt()),
      ];
    } on Object {
      return const [];
    }
  }

  static String encode(List<LimitItem> l) => jsonEncode([for (final i in l) i.toMap()]);
}

final _hostRe = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$');

/// The host of what the user typed ("https://www.Example.com:8080/a" and "example.com/a" both give example.com); null if it is not a site.
String? hostOf(String address) {
  var a = address.trim().toLowerCase();
  if (a.isEmpty || a.contains(RegExp(r'\s'))) return null;
  final i = a.indexOf('://');
  if (i >= 0) a = a.substring(i + 3);
  a = a.split(RegExp(r'[/?#]')).first;
  a = a.split('@').last.split(':').first;
  if (a.startsWith('www.')) a = a.substring(4);
  while (a.endsWith('.')) {
    a = a.substring(0, a.length - 1);
  }
  return _hostRe.hasMatch(a) ? a : null;
}

/// True when [after] is no looser than [before]: every limit in force is still there and not longer. Such a change starts at once;
/// anything else needs the 30 second hold and starts at the next midnight.
bool isStricter(List<LimitItem> before, List<LimitItem> after) {
  final m = {for (final i in after) i.key: i.limitMin};
  return before.every((b) => m[b.key] != null && m[b.key]! <= b.limitMin);
}

/// A stable text for comparing two lists (the order the user added them in does not matter).
String limitsSignature(List<LimitItem> l) => LimitItem.encode([...l]..sort((a, b) => a.key.compareTo(b.key)));

class LimitsState {
  final List<LimitItem> active;
  final List<LimitItem>? pending;
  final int pendingFrom;
  final Map<String, int> used;

  /// Usage access is what times the apps; without it an app limit cannot count or block.
  final bool usageAccess;

  /// "Display over other apps": lets the app send you to the home screen when an app has used its time. And the website filter (a local VPN that only carries DNS questions).
  final bool overlay;
  final bool siteFilter;

  /// How websites are blocked: `vpn` (a local filter on DNS look-ups) or `access` (the browser's address bar, read with Accessibility).
  final String siteMethod;

  /// Accessibility is running and the user allowed reading the screens, so the `access` method can work.
  final bool accessReady;
  const LimitsState(this.active, this.pending, this.pendingFrom, this.used, this.usageAccess,
      {this.overlay = false, this.siteFilter = false, this.siteMethod = 'vpn', this.accessReady = false});
}

class InstalledApp {
  final String pkg;
  final String label;
  const InstalledApp(this.pkg, this.label);
}

/// The time limits for apps and websites, on the `reelbot/counter` channel. Full build only.
class LimitsBridge {
  static const _ch = MethodChannel('reelbot/counter');

  Future<LimitsState> state() async {
    final m = (await _ch.invokeMapMethod<String, dynamic>('limitsState'))!;
    final p = m['pending'] as String?;
    return LimitsState(
      LimitItem.parse(m['active'] as String?),
      p == null ? null : LimitItem.parse(p),
      (m['pendingFrom'] as num?)?.toInt() ?? 0,
      {for (final e in (m['used'] as Map? ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
      m['usageAccess'] == true,
      overlay: m['overlay'] == true,
      siteFilter: m['siteFilter'] == true,
      siteMethod: m['siteMethod'] == 'access' ? 'access' : 'vpn',
      accessReady: m['accessReady'] == true,
    );
  }

  /// "ok" or "invalid". [immediate]: the change is no looser than what is in force.
  Future<String> save(List<LimitItem> items, {required bool immediate}) async =>
      (await _ch.invokeMethod<String>('limitsSave', {'items': LimitItem.encode(items), 'immediate': immediate}))!;

  Future<void> setSiteMethod(String method) => _ch.invokeMethod('setSiteMethod', {'method': method});

  Future<void> remove() => _ch.invokeMethod('limitsRemove');

  Future<List<InstalledApp>> installedApps() async => [
        for (final m in await _ch.invokeListMethod<Map>('installedApps') ?? const <Map>[]) InstalledApp('${m['pkg']}', '${m['label']}'),
      ];
}
