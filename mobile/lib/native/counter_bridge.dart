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

  /// Opens Android's share sheet with [text].
  Future<void> shareText(String text, {String? subject}) => _ch.invokeMethod('shareText', {'text': text, 'subject': subject});

  /// Deletes files in the app's photo folder that aren't in [keep].
  Future<void> sweepPhotos(List<String> keep) => _ch.invokeMethod('sweepPhotos', {'keep': keep});

  /// Dead-man's switch for an analysis run in the app: if it is not pushed back (by calling this again) or disarmed,
  /// the background task restarts the analysis about 100 seconds later. Covers the app being killed mid-run.
  Future<void> armWatchdog() => _ch.invokeMethod('armWatchdog');
  Future<void> disarmWatchdog() => _ch.invokeMethod('disarmWatchdog');

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
}
