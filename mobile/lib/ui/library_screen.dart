import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/models.dart';
import 'chat_screen.dart';
import 'reel_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';

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
    final hasKey = (await s.keys.geminiKeys).isNotEmpty || await s.keys.openai != null || await s.keys.claude != null;
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
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: () => _open(SettingsScreen(s))),
        ],
      ),
      floatingActionButton: _reels.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _open(ChatScreen(s)),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Ask your reels'),
            ),
      body: RefreshIndicator(
        onRefresh: _process,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            SearchBar(
              hintText: 'Search your notes',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (q) {
                _query = q;
                _reload();
              },
            ),
            const SizedBox(height: 12),
            if (!_hasKey)
              _Banner(
                icon: Icons.key_rounded,
                text: 'Add a Gemini key (free) in Settings to turn reels into notes.',
                onTap: () => _open(SettingsScreen(s)),
              ),
            if (_waiting > 0)
              _Banner(
                icon: _busy ? null : Icons.schedule,
                text: '$_waiting waiting to be analysed',
                detail: s.runner.lastProblem,
              ),
            if (_reels.isEmpty && _waiting == 0)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Column(children: [
                  const BrandMark(size: 80),
                  const SizedBox(height: 24),
                  Text('Nothing saved yet', style: t.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('In Instagram or YouTube, tap Share → Reel Bot on a reel or short.',
                      textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ]),
              ),
            for (final r in _reels) _ReelCard(r, onTap: () => _open(ReelScreen(s, r))),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData? icon;
  final String text;
  final String? detail;
  final VoidCallback? onTap;
  const _Banner({required this.icon, required this.text, this.detail, this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: icon == null ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon),
            title: Text(text),
            subtitle: detail == null ? null : Text(detail!, maxLines: 3, overflow: TextOverflow.ellipsis),
            onTap: onTap,
          ),
        ),
      );
}

class _ReelCard extends StatelessWidget {
  final Reel reel;
  final VoidCallback onTap;
  const _ReelCard(this.reel, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final yt = reel.app == 'youtube';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(10)),
                    child: Icon(yt ? Icons.smart_display_rounded : Icons.movie_rounded, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(reel.author.isEmpty ? (yt ? 'YouTube' : 'Instagram') : '@${reel.author}',
                        style: t.textTheme.labelLarge, overflow: TextOverflow.ellipsis),
                  ),
                  if (reel.analysis != 'done') Icon(Icons.text_snippet_outlined, size: 16, color: t.colorScheme.outline),
                ]),
                const SizedBox(height: 10),
                Text(reel.title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (reel.summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(reel.summary, maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ],
                if (reel.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final tag in reel.tags.take(4))
                      Text('#$tag', style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary)),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
