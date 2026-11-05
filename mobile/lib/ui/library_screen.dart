import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../core/models.dart';
import 'archive_screen.dart';
import 'reel_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'liquid.dart';

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
    await s.library.archiveOld(DateTime.now().millisecondsSinceEpoch);
    final reels = await s.library.reels(query: _query, archived: false);
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
    return LiquidScaffold(
      background: false,
      appBar: AppBar(
        title: const Text('Library', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(tooltip: 'Archive', icon: const Icon(Icons.inventory_2_outlined), onPressed: () => _open(ArchiveScreen(s))),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: () => _open(SettingsScreen(s))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _process,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), // clear of the floating tab bar
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
            if (_reels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Swipe left to delete, right to archive. Seen notes archive themselves after 3 days.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ),
            for (final r in _reels) SwipeNote(s, r, onTap: () => _open(ReelScreen(s, r)), onChanged: _reload),
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
          child: ListTile(
            leading: icon == null ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon),
            title: Text(text),
            subtitle: detail == null ? null : Text(detail!, maxLines: 3, overflow: TextOverflow.ellipsis),
            onTap: onTap,
          ),
        ),
      );
}

/// A note card you can swipe: left deletes (with Undo), right archives it, or restores it in the archive.
class SwipeNote extends StatelessWidget {
  final AppServices services;
  final Reel reel;
  final VoidCallback onTap;
  final VoidCallback onChanged;
  const SwipeNote(this.services, this.reel, {required this.onTap, required this.onChanged, super.key});

  Future<void> _delete(BuildContext context) async {
    HapticFeedback.heavyImpact();
    await services.library.delete(reel.url);
    onChanged();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Note deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () async {
          await services.library.saveReel(reel);
          onChanged();
        }),
      ));
  }

  Widget _bg(BuildContext context, Alignment a, IconData icon, String label, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: a,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(reel.url),
      background: _bg(context, Alignment.centerLeft, reel.archived ? Icons.unarchive_rounded : Icons.archive_rounded,
          reel.archived ? 'Restore' : 'Archive', Brand.violet),
      secondaryBackground: _bg(context, Alignment.centerRight, Icons.delete_rounded, 'Delete', c.error),
      onDismissed: (dir) async {
        if (dir == DismissDirection.endToStart) return _delete(context);
        HapticFeedback.mediumImpact();
        await services.library.setArchived(reel.url, !reel.archived);
        onChanged();
      },
      child: ReelCard(reel, onTap: onTap, onDelete: () => _delete(context)),
    );
  }
}

/// A note in a list; a gradient dot marks one you haven't opened yet.
class ReelCard extends StatelessWidget {
  final Reel reel;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const ReelCard(this.reel, {required this.onTap, this.onDelete, super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final yt = reel.app == 'youtube';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
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
                  Text(savedAgo(reel.savedAt, DateTime.now()), style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                  if (reel.analysis != 'done') Icon(Icons.text_snippet_outlined, size: 16, color: t.colorScheme.outline),
                  if (reel.seenAt == 0)
                    Semantics(
                      label: 'Not seen yet',
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
                      ),
                    ),
                  if (onDelete != null)
                    SizedBox.square(
                      dimension: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Delete',
                        iconSize: 18,
                        icon: Icon(Icons.delete_outline, color: t.colorScheme.outline),
                        onPressed: onDelete,
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                Text(reel.title,
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: reel.seenAt == 0 ? FontWeight.w700 : FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (reel.summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(reel.summary, maxLines: 2, overflow: TextOverflow.ellipsis,
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
