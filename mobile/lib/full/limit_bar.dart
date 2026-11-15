import 'package:flutter/material.dart';

/// How full a daily limit is, 0 to 1 (a bar never overflows, and a zero limit counts as full).
double limitFraction(int usedMs, int limitMin) => limitMin <= 0 ? 1 : (usedMs / (limitMin * 60000)).clamp(0.0, 1.0);

String minutesText(int m) => m % 60 == 0 && m >= 60 ? '${m ~/ 60} h' : m > 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';

/// One timer: a label, the time used against the limit, and a bar that turns to the error colour when the time is used up.
class LimitBar extends StatelessWidget {
  final String label;
  final int usedMs;
  final int limitMin;
  const LimitBar({required this.label, required this.usedMs, required this.limitMin, super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = limitFraction(usedMs, limitMin);
    final full = f >= 1;
    final used = (usedMs / 60000).floor();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: t.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
          Text('${minutesText(used)} of ${minutesText(limitMin)}', style: t.textTheme.bodySmall),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 8,
            color: full ? t.colorScheme.error : t.colorScheme.primary,
            backgroundColor: t.colorScheme.surfaceContainerHighest,
          ),
        ),
      ]),
    );
  }
}
