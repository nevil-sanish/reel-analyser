import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../native/counter_bridge.dart';

/// What the counter sees, and the screen-structure capture used to fix DetectionRules.kt (IMPLEMENTATION §3.0).
class DebugScreen extends StatefulWidget {
  final AppServices services;
  const DebugScreen(this.services, {super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  CounterBridge get b => widget.services.bridge;
  Map<String, String> _state = {};
  List<SeenItem> _seen = [];
  DayTotal? _today;
  bool _capture = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await b.debugState();
    final seen = await b.seenItems(localDate());
    final days = await b.history(days: 1);
    final status = await b.status();
    if (!mounted) return;
    setState(() {
      _state = state;
      _seen = seen;
      _today = days.firstOrNull;
      _capture = status.capture;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final now = _state['now'];
    return Scaffold(
      appBar: AppBar(title: const Text('Counter debug'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Unreadable today: ${_today?.unknown ?? 0} · counted: ${_today?.reels ?? 0}'),
          const Divider(),
          Text('What the counter sees now', style: Theme.of(context).textTheme.titleSmall),
          Text(now == null ? 'Nothing yet. Turn on capture, open a reel, come back.' : const JsonEncoder.withIndent('  ').convert(jsonDecode(now)),
              style: mono),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Capture screen structure'),
            subtitle: const Text('Open Reels or Shorts with this on, then come back and copy the trees. '
                'Turning it off deletes what it recorded.'),
            value: _capture,
            onChanged: (v) async {
              await b.setCapture(v);
              _load();
            },
          ),
          for (final app in ['instagram', 'youtube'])
            if (_state['tree_$app'] case final tree?)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('tree_$app'),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => Clipboard.setData(ClipboardData(text: tree)),
                ),
                children: [SelectableText(tree, style: mono)],
              ),
          if (_state['autosave_tries'] case final tries?)
            Text('Auto-Save: ${_state['autosave_ok'] ?? '0'} of $tries worked (keep it only above 90%) · '
                'last: ${_state['autosave_last'] ?? ''}'),
          const Divider(),
          Text('Seen today: ${_seen.length} reels. Reel Bot keeps only an anonymous fingerprint of each, never what it was.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
