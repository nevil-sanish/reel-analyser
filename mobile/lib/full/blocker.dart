import 'dart:convert';

import 'package:flutter/services.dart';

/// A span of the day in minutes since midnight. `start > end` runs over midnight.
class TimeSlot {
  final int start;
  final int end;
  const TimeSlot(this.start, this.end);

  static String hhmm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  @override
  String toString() => '${hhmm(start)} - ${hhmm(end)}';
  @override
  bool operator ==(Object other) =>
      other is TimeSlot && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
}

/// At most [limitMin] minutes of reels a day (null = no limit), and only inside [intervals] (empty = any time).
class BlockRule {
  final int? limitMin;
  final List<TimeSlot> intervals;
  const BlockRule(this.limitMin, this.intervals);
}

const blockSurfaces = ['instagram', 'youtube', 'browser'];
const surfaceNames = {
  'instagram': 'Instagram Reels',
  'youtube': 'YouTube Shorts',
  'browser': 'Browser (reels and shorts pages)',
};

/// What the user chose to block. `shared`: one rule under `all` covers the chosen items together; `separate`: one each.
class BlockConfig {
  final String mode;
  final Set<String> items;
  final Map<String, BlockRule> rules;
  const BlockConfig(this.mode, this.items, this.rules);

  String toJson() => jsonEncode({
    'mode': mode,
    'items': items.toList()..sort(),
    'rules': {
      for (final e in rules.entries)
        e.key: {
          'limitMin': e.value.limitMin,
          'intervals': [
            for (final i in e.value.intervals) [i.start, i.end],
          ],
        },
    },
  });

  static BlockConfig? parse(String? json) {
    if (json == null) return null;
    try {
      final o = jsonDecode(json) as Map;
      return BlockConfig(
        o['mode'] as String,
        {for (final i in o['items'] as List) '$i'},
        {
          for (final e in (o['rules'] as Map).entries)
            '${e.key}': BlockRule((e.value['limitMin'] as num?)?.toInt(), [
              for (final i in e.value['intervals'] as List)
                TimeSlot((i[0] as num).toInt(), (i[1] as num).toInt()),
            ]),
        },
      );
    } on Object {
      return null;
    }
  }
}

class BlockerState {
  final BlockConfig? active;
  final BlockConfig? pending;
  final int pendingFrom;
  final bool suspendedToday;
  final String? photo;
  final bool editable;
  final int nextEdit;
  final Map<String, int> used;

  const BlockerState({
    this.active,
    this.pending,
    this.pendingFrom = 0,
    this.suspendedToday = false,
    this.photo,
    this.editable = true,
    this.nextEdit = 0,
    this.used = const {},
  });

  factory BlockerState.fromMap(Map m) => BlockerState(
    active: BlockConfig.parse(m['active'] as String?),
    pending: BlockConfig.parse(m['pending'] as String?),
    pendingFrom: (m['pendingFrom'] as num?)?.toInt() ?? 0,
    suspendedToday: m['suspendedToday'] == true,
    photo: m['photo'] as String?,
    editable: m['editable'] != false,
    nextEdit: (m['nextEdit'] as num?)?.toInt() ?? 0,
    used: {
      for (final e in (m['used'] as Map? ?? const {}).entries)
        '${e.key}': (e.value as num).toInt(),
    },
  );
}

class BlockEvent {
  final DateTime at;
  final String kind;
  final String surface;
  const BlockEvent(this.at, this.kind, this.surface);

  /// One line for the history list.
  String get label {
    final what = surface.isEmpty
        ? ''
        : ' (${surfaceNames[surface]?.split(' (').first ?? surface})';
    return switch (kind) {
      'limit' => 'Reached the daily limit$what',
      'schedule' => 'Tried to watch outside the schedule$what',
      'cancel_try' => 'Tried to cancel the block$what',
      'cancelled' => 'Cancelled the block for the day$what',
      'kept' => 'Kept the block$what',
      'set' => 'Set up the blocker',
      'changed' => 'Changed the rules',
      'removed' => 'Removed the blocker for good',
      _ => kind,
    };
  }
}

/// The reel blocker's side of the `reelbot/counter` channel. Full build only: the semi build answers "not implemented".
class BlockerBridge {
  static const _ch = MethodChannel('reelbot/counter');

  Future<BlockerState> state() async => BlockerState.fromMap(
    (await _ch.invokeMapMethod<String, dynamic>('blockState'))!,
  );

  /// "ok", "locked" or "invalid".
  Future<String> save(BlockConfig c) async =>
      (await _ch.invokeMethod<String>('blockSave', {'config': c.toJson()}))!;

  /// Has the user opted in to reading the reel screens? Until then the Accessibility service reads nothing.
  Future<bool> consent() async => await _ch.invokeMethod<bool>('detectionConsent') ?? false;

  Future<void> setConsent(bool on) => _ch.invokeMethod('setDetectionConsent', {'on': on});

  /// Tells the blocker which apps are blocked for missed daily goals, and through which day (yyyy-MM-dd, inclusive).
  Future<void> punishSet({required String? until, required Set<String> apps, required int streak}) =>
      _ch.invokeMethod('punishSet', {'until': until, 'apps': apps.toList(), 'streak': streak});

  Future<void> removeForGood() => _ch.invokeMethod('blockRemove');

  /// Opens the photo flow that cancels the block for today.
  Future<void> cancelToday() => _ch.invokeMethod('blockCancel');

  Future<List<BlockEvent>> history() async => [
    for (final e
        in await _ch.invokeListMethod<Map>('blockHistory') ?? const <Map>[])
      BlockEvent(
        DateTime.fromMillisecondsSinceEpoch((e['ts'] as num).toInt()),
        '${e['kind']}',
        '${e['surface']}',
      ),
  ];
}

/// The "why do you want to remove it?" paragraph must be typed. Nothing can tell for sure that a text was not written by an AI,
/// so this refuses what a person would not type: a big chunk arriving at once (a paste), too little, too fast, or
/// wording and characters that are typical of AI output.
class ParagraphGuard {
  /// The most characters one edit may add. A suggestion or a swiped word fits; a pasted sentence does not.
  static const maxJump = 20;
  static const minWords = 50;
  static const minTyping = Duration(seconds: 90);

  static const _tells = [
    'as an ai',
    'language model',
    'delve',
    'tapestry',
    "it's important to note",
    'it is important to note',
    'in conclusion',
    'furthermore',
    'moreover',
    'i cannot',
    'certainly!',
  ];

  String _text = '';
  DateTime? _first;
  DateTime? _last;

  String get text => _text;

  /// Takes the field's new value; false when it must be refused (the caller puts the old text back).
  bool accept(String next, DateTime now) {
    if (next.length - _text.length > maxJump) return false;
    _first ??= now;
    _last = now;
    _text = next;
    return true;
  }

  Duration get typedFor =>
      _first == null ? Duration.zero : _last!.difference(_first!);

  /// A message for what is wrong, or null when the paragraph is accepted.
  String? check() {
    final words = _text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    if (words < minWords) {
      return 'Write at least $minWords words ($words so far).';
    }
    if (typedFor < minTyping) {
      return 'Take your time: this has to be written by hand, not quickly.';
    }
    final l = _text.toLowerCase();
    if (l.contains('—') || l.contains('–') || _tells.any(l.contains)) {
      return 'This reads like text from an AI. Write it in your own words.';
    }
    return null;
  }
}
