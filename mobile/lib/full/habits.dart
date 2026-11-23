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

/// What the phone's own numbers say about the user's scrolling. Worked out on the phone from the counter and Usage access;
/// it only suggests, and nothing is enforced that the user did not set.
class Habits {
  final List<int> peakHours;
  final double lateNightShare;
  final double averageReels;
  final int todayReels;
  final int suggestedMaxSwipes;
  const Habits(this.peakHours, this.lateNightShare, this.averageReels, this.todayReels, this.suggestedMaxSwipes);

  bool get todayAboveAverage => averageReels >= 10 && todayReels >= averageReels * 1.3;
  bool get lateNightHeavy => lateNightShare >= 0.25;

  /// [hourlyMs]: 24 values, time per hour of the day. [reelsPerDay]: reels per day, today first.
  static Habits analyse(List<int> hourlyMs, List<int> reelsPerDay) {
    final total = hourlyMs.fold(0, (a, b) => a + b);
    final order = [for (var h = 0; h < 24; h++) h]..sort((a, b) => hourlyMs[b].compareTo(hourlyMs[a]));
    final peaks = [for (final h in order.take(3)) if (hourlyMs[h] > 0) h]..sort();
    var late = 0;
    for (var h = 0; h < 24; h++) {
      if (h >= 22 || h < 5) late += hourlyMs[h];
    }
    final past = [for (final r in reelsPerDay.skip(1)) if (r > 0) r];
    final avg = past.isEmpty ? 0.0 : past.fold(0, (a, b) => a + b) / past.length;
    final suggested = avg < 10 ? 0 : (((avg * 0.8) / 10).round() * 10).clamp(20, 5000);
    return Habits(peaks, total == 0 ? 0 : late / total, avg, reelsPerDay.isEmpty ? 0 : reelsPerDay.first, suggested);
  }

  /// Plain sentences for the screen.
  List<String> notes() => [
        if (peakHours.isNotEmpty) 'You scroll most around ${peakHours.map((h) => '${h.toString().padLeft(2, '0')}:00').join(', ')}.',
        if (lateNightHeavy) '${(lateNightShare * 100).round()}% of your time is between 22:00 and 05:00. A burst pause helps at night.',
        if (averageReels >= 10) 'Your usual day is about ${averageReels.round()} reels or shorts.',
        if (todayAboveAverage) 'Today is already well above your usual.',
      ];
}
