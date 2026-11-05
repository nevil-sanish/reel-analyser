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
}
