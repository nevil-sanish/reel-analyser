import 'dart:convert';

import 'package:flutter/services.dart';

/// The scroll guard rule: most swipes a day, and most swipes in a run (a run ends after [quietSec] seconds without a swipe).
/// Past either the app is closed and the phone goes home. 0 turns a part off. Same shape as Kotlin's `ScrollRule`.
class ScrollRule {
  final int maxPerDay, runSwipes, quietSec, pauseMinutes;
  const ScrollRule({this.maxPerDay = 0, this.runSwipes = 0, this.quietSec = 30, this.pauseMinutes = 5});

  bool get on => maxPerDay > 0 || runSwipes > 0;

  String toJson() => jsonEncode({'maxPerDay': maxPerDay, 'runSwipes': runSwipes, 'quietSec': quietSec, 'pauseMinutes': pauseMinutes});

  static ScrollRule? parse(String? json) {
    if (json == null) return null;
    try {
      final o = jsonDecode(json) as Map;
      return ScrollRule(
        maxPerDay: (o['maxPerDay'] as num).toInt(),
        runSwipes: (o['runSwipes'] as num).toInt(),
        quietSec: (o['quietSec'] as num).toInt(),
        pauseMinutes: (o['pauseMinutes'] as num).toInt(),
      );
    } on Object {
      return null;
    }
  }

  /// True when this rule is no looser than [before]: a part that was on stays on and is not weaker. Such a change starts at
  /// once; anything else takes the 30 second hold, like loosening a limit.
  bool noLooserThan(ScrollRule before) {
    final dayOk = before.maxPerDay == 0 || (maxPerDay > 0 && maxPerDay <= before.maxPerDay);
    final runOk = before.runSwipes == 0 ||
        (runSwipes > 0 && runSwipes <= before.runSwipes && quietSec >= before.quietSec && pauseMinutes >= before.pauseMinutes);
    return dayOk && runOk;
  }
}

class ScrollState {
  final ScrollRule? rule;
  final int swipesToday;
  const ScrollState(this.rule, this.swipesToday);
}

class ScrollBridge {
  static const _ch = MethodChannel('reelbot/counter');

  Future<ScrollState> state() async {
    final m = (await _ch.invokeMapMethod<String, dynamic>('scrollState'))!;
    return ScrollState(ScrollRule.parse(m['rule'] as String?), (m['swipesToday'] as num?)?.toInt() ?? 0);
  }

  /// "ok" or "invalid". Switching it off is a rule with every part 0.
  Future<String> save(ScrollRule r) async => (await _ch.invokeMethod<String>('scrollSave', {'rule': r.toJson()}))!;
}
