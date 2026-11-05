import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/models.dart';
import 'ask_screen.dart';
import 'reel_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  final AppServices services;
  const LibraryScreen(this.services, {super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with WidgetsBindingObserver {
  AppServices get s => widget.services;
  List<Reel> _reels = [];
  int _waiting = 0;
  bool _hasKey = true;
  bool _busy = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _process();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _process();
  }

  Future<void> _reload() async {
    final reels = await s.library.reels(query: _query);
    final waiting = (await s.bridge.pendingItems(status: 'queued')).length;
    final hasKey = await s.keys.gemini != null;
    if (!mounted) return;
    setState(() {
      _reels = reels;
      _waiting = waiting;
      _hasKey = hasKey;
    });
  }

  Future<void> _process() async {
    await _reload();
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await s.runner.processQueue();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _reload();
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _process();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reel Bot'),
        actions: [
          IconButton(tooltip: 'Ask your library', icon: const Icon(Icons.forum_outlined), onPressed: () => _open(AskScreen(s))),
          IconButton(tooltip: 'Your AI keys', icon: const Icon(Icons.key_outlined), onPressed: () => _open(SettingsScreen(s))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _process,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SearchBar(
                hintText: 'Search your notes',
                leading: const Icon(Icons.search),
                onChanged: (q) {
                  _query = q;
                  _reload();
                },
              ),
            ),
            if (!_hasKey)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('Add your Gemini API key in Settings to analyze reels.'),
                  onTap: () => _open(SettingsScreen(s)),
                ),
              ),
            if (_waiting > 0)
              ListTile(
                leading: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.schedule),
                title: Text('$_waiting waiting to be analysed'),
                subtitle: s.runner.lastProblem == null ? null : Text(s.runner.lastProblem!),
              ),
            if (_reels.isEmpty && _waiting == 0)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing here yet.\n\nIn Instagram or YouTube, tap Share → Reel Bot on a reel or short. '
                  'It gets summarised in the background.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final r in _reels)
              ListTile(
                leading: Icon(r.app == 'youtube' ? Icons.smart_display_outlined : Icons.movie_outlined),
                title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [if (r.author.isNotEmpty) '@${r.author}', ...r.tags.take(3).map((t) => '#$t')].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: r.analysis == 'done' ? null : const Icon(Icons.subject, size: 18),
                onTap: () => _open(ReelScreen(s, r)),
              ),
          ],
        ),
      ),
    );
  }
}
