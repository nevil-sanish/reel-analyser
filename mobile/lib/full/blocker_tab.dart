import 'package:flutter/material.dart';

import '../app_services.dart';
import '../ui/liquid.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import 'blocker_screen.dart';
import 'goals_screen.dart';
import 'limits_screen.dart';

/// The Blocker tab: the reel limits and schedules, and the daily goals, one under a switch. Tabs stay alive behind each other, so
/// the page is rebuilt each time the tab comes back and always shows what the blocker holds now.
class BlockerTab extends StatefulWidget {
  final AppServices services;
  final bool active;
  const BlockerTab(this.services, {required this.active, super.key});

  @override
  State<BlockerTab> createState() => _BlockerTabState();
}

class _BlockerTabState extends State<BlockerTab> {
  var _page = 0; // 0 = reel limits, 1 = apps and sites, 2 = daily goals
  var _epoch = 0;

  @override
  void didUpdateWidget(BlockerTab old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active) setState(() => _epoch++);
  }

  @override
  Widget build(BuildContext context) => LiquidScaffold(
        background: false,
        appBar: AppBar(
          title: const Text('Blocker'),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 0, label: Text('Reel limits')), ButtonSegment(value: 1, label: Text('Apps & sites')), ButtonSegment(value: 2, label: Text('Daily goals'))],
                selected: {_page},
                onSelectionChanged: (v) {
                  Haptics.select();
                  setState(() => _page = v.first);
                },
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Brand.reduceEffects.value ? Duration.zero : const Duration(milliseconds: 280),
              child: KeyedSubtree(
                key: ValueKey('$_page-$_epoch'),
                child: switch (_page) {
                  0 => BlockerScreen(widget.services, embedded: true),
                  1 => LimitsScreen(widget.services),
                  _ => GoalsScreen(widget.services, embedded: true),
                },
              ),
            ),
          ),
        ]),
      );
}
