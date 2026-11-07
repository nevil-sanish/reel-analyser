import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../core/models.dart';
import '../pipeline/runner.dart';
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
  String _kind = 'all';
  final _selected = <String>{};

  List<Reel> get _visible => [for (final r in _reels) if (_kind == 'all' || r.kind == _kind) r];

  void _toggle(Reel r) => setState(() => _selected.contains(r.url) ? _selected.remove(r.url) : _selected.add(r.url));
  static const _kinds = {'all': 'All', 'reel': 'Reels', 'short': 'Shorts', 'post': 'Posts', 'photo': 'Photos'};
  int _waiting = 0;
  bool _hasKey = true;
  bool _busy = false;
  Timer? _poll;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _process();
    // Reels shared while this screen is open, or left queued by a rate limit, are picked up without a restart.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted || _busy) return;
      await _reload();
      if (mounted && _waiting > 0) _process();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
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
      appBar: _selected.isNotEmpty
          ? selectionBar(
              count: _selected.length,
              archived: false,
              onClose: () => setState(_selected.clear),
              onAll: () => setState(() => _selected.addAll(_visible.map((r) => r.url))),
              onAction: (a) async {
                final picked = [for (final r in _reels) if (_selected.contains(r.url)) r];
                setState(_selected.clear);
                await bulkAction(context, s, picked, a, _reload);
              },
            )
          : AppBar(
              title: const Text('Library', style: TextStyle(fontWeight: FontWeight.w700)),
              actions: [
                IconButton(tooltip: 'Archive', icon: const Icon(Icons.inventory_2_outlined), onPressed: () => _open(ArchiveScreen(s))),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: _process,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120), // clear of the floating tab bar
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final k in _kinds.entries)
                  if (k.key == 'all' || _reels.any((r) => r.kind == k.key))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${k.value} ${k.key == 'all' ? _reels.length : _reels.where((r) => r.kind == k.key).length}'),
                      selected: _kind == k.key,
                      showCheckmark: false,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _kind = k.key);
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            if (!_hasKey)
              _Banner(
                icon: Icons.key_rounded,
                text: 'Add a Gemini key (free) in Settings to turn reels into notes.',
                onTap: () => _open(SettingsScreen(s)),
              ),
            ValueListenableBuilder<List<Job>>(
              valueListenable: s.runner.jobs,
              builder: (context, jobs, _) => jobs.isEmpty ? const SizedBox.shrink() : _JobsCard(jobs, s.runner.cancel),
            ),
            if (_waiting > 0 && s.runner.jobs.value.isEmpty)
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
                  Text('In Instagram or YouTube, tap Share → Reel Analyser on a reel or short.',
                      textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ]),
              ),
            for (final r in _visible)
              SwipeNote(s, r,
                  selected: _selected.isEmpty ? null : _selected.contains(r.url),
                  onLongPress: () => _toggle(r),
                  onTap: () => _selected.isEmpty ? _open(ReelScreen(s, r, onChanged: _reload)) : _toggle(r),
                  onChanged: _reload),
          ],
        ),
      ),
    );
  }
}

/// Every reel in the current run with its own progress bar and a Stop button.
class _JobsCard extends StatelessWidget {
  final List<Job> jobs;
  final Future<void> Function(int id) onStop;
  const _JobsCard(this.jobs, this.onStop);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final active = jobs.where((j) => j.active).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(active > 0 ? 'Analysing $active ${active == 1 ? 'reel' : 'reels'}' : 'Analysis finished',
                style: t.textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final j in jobs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(
                    switch (j.state) {
                      JobState.done => Icons.check_circle_rounded,
                      JobState.failed || JobState.retry => Icons.error_outline_rounded,
                      JobState.stopped => Icons.stop_circle_outlined,
                      _ => j.app == 'youtube' ? Icons.smart_display_outlined : j.app == 'photo' ? Icons.image_outlined : Icons.movie_outlined,
                    },
                    size: 22,
                    color: j.state == JobState.done ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(j.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyLarge),
                      Text(j.stage, maxLines: 4, overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                      if (j.state == JobState.running || j.state == JobState.waiting)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: j.state == JobState.waiting ? 0 : j.progress, minHeight: 5),
                          ),
                        ),
                    ]),
                  ),
                  if (j.state != JobState.done && j.state != JobState.stopped)
                    IconButton(
                      tooltip: j.state == JobState.failed ? 'Dismiss' : 'Stop analysing this reel',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onStop(j.id);
                      },
                    ),
                ]),
              ),
          ]),
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

  /// Multi-select: null when not selecting; otherwise whether this note is ticked. Long-press starts it.
  final bool? selected;
  final VoidCallback? onLongPress;
  const SwipeNote(this.services, this.reel,
      {required this.onTap, required this.onChanged, this.selected, this.onLongPress, super.key});

  Future<void> _delete(BuildContext context) async {
    HapticFeedback.heavyImpact();
    await services.library.delete(reel.url);
    onChanged();
    if (!context.mounted) return;
    showUndo(ScaffoldMessenger.of(context), 'Note deleted', () => services.library.saveReel(reel), onChanged);
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
      direction: selected == null ? DismissDirection.horizontal : DismissDirection.none,
      background: _bg(context, Alignment.centerLeft, reel.archived ? Icons.unarchive_rounded : Icons.archive_rounded,
          reel.archived ? 'Restore' : 'Archive', Brand.emerald),
      secondaryBackground: _bg(context, Alignment.centerRight, Icons.delete_rounded, 'Delete', c.error),
      onDismissed: (dir) async {
        if (dir == DismissDirection.endToStart) return _delete(context);
        HapticFeedback.mediumImpact();
        await services.library.setArchived(reel.url, !reel.archived);
        onChanged();
        if (!context.mounted) return;
        showUndo(ScaffoldMessenger.of(context), reel.archived ? 'Note restored' : 'Note archived',
            () => services.library.setArchived(reel.url, reel.archived), onChanged);
      },
      child: ReelCard(reel, onTap: onTap, onLongPress: onLongPress, selected: selected),
    );
  }
}

/// A note in a list; a gradient dot marks one you haven't opened yet.
class ReelCard extends StatelessWidget {
  final Reel reel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool? selected;
  const ReelCard(this.reel, {required this.onTap, this.onLongPress, this.selected, super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final yt = reel.app == 'youtube';
    final photo = reel.app == 'photo';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: selected == true
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: t.colorScheme.primary, width: 2))
            : null,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          onLongPress: onLongPress == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onLongPress!();
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
                    child: Icon(photo ? Icons.photo_rounded : yt ? Icons.smart_display_rounded : Icons.movie_rounded,
                        size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(reel.author.isEmpty ? (photo ? 'Photo' : yt ? 'YouTube' : 'Instagram') : '@${reel.author}',
                        style: t.textTheme.labelLarge, overflow: TextOverflow.ellipsis),
                  ),
                  Text(savedAgo(reel.savedAt, DateTime.now()), style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                  if (selected != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(selected! ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 22, color: selected! ? t.colorScheme.primary : t.colorScheme.outline),
                    )
                  else if (reel.seenAt == 0)
                    Semantics(
                      label: 'Not seen yet',
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
                      ),
                    ),
                ]),
                if (photo) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(File(reel.url.substring('photo:'.length)),
                        height: 140, width: double.infinity, fit: BoxFit.cover, cacheWidth: 600,
                        errorBuilder: (_, _, _) => const SizedBox()),
                  ),
                ],
                const SizedBox(height: 10),
                Text(reel.title,
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: reel.seenAt == 0 ? FontWeight.w700 : FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (reel.overview.isNotEmpty || reel.summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(reel.overview.isEmpty ? reel.summary : reel.overview.take(2).map((o) => '• $o').join('\n'),
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.35)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Multi-select toolbar for the Library and the Archive: count, select all, mark read, archive or restore, delete.
PreferredSizeWidget selectionBar({
  required int count,
  required VoidCallback onClose,
  required VoidCallback onAll,
  required bool archived,
  required Future<void> Function(String action) onAction,
}) =>
    AppBar(
      leading: IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close_rounded), onPressed: onClose),
      title: Text('$count selected'),
      actions: [
        IconButton(tooltip: 'Select all', icon: const Icon(Icons.select_all_rounded), onPressed: onAll),
        IconButton(tooltip: 'Mark read', icon: const Icon(Icons.done_all_rounded), onPressed: () => onAction('read')),
        IconButton(tooltip: 'Mark unread', icon: const Icon(Icons.mark_email_unread_outlined), onPressed: () => onAction('unread')),
        IconButton(
          tooltip: archived ? 'Restore' : 'Archive',
          icon: Icon(archived ? Icons.unarchive_outlined : Icons.archive_outlined),
          onPressed: () => onAction(archived ? 'restore' : 'archive'),
        ),
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => onAction('delete')),
      ],
    );

/// Applies a bulk action to [reels]; every action offers Undo.
Future<void> bulkAction(BuildContext context, AppServices s, List<Reel> reels, String action, VoidCallback onDone) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  action == 'delete' ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
  for (final r in reels) {
    switch (action) {
      case 'read':
        await s.library.markSeen(r.url, now);
      case 'unread':
        await s.library.markUnseen(r.url);
      case 'archive' || 'restore':
        await s.library.setArchived(r.url, action == 'archive');
      case 'delete':
        await s.library.delete(r.url);
    }
  }
  onDone();
  if (!context.mounted) return;
  final n = reels.length == 1 ? '1 note' : '${reels.length} notes';
  showUndo(
    ScaffoldMessenger.of(context),
    switch (action) { 'read' => '$n marked read', 'unread' => '$n marked unread', 'archive' => '$n archived', 'restore' => '$n restored', _ => '$n deleted' },
    () async {
      for (final r in reels) {
        switch (action) {
          case 'read':
            if (r.seenAt == 0) await s.library.markUnseen(r.url); // only the ones that were unread
          case 'unread':
            if (r.seenAt > 0) await s.library.markSeen(r.url, r.seenAt); // only the ones that were read
          case 'archive' || 'restore':
            await s.library.setArchived(r.url, r.archived);
          case 'delete':
            await s.library.saveReel(r);
        }
      }
    },
    onDone,
  );
}

/// "Note deleted · Undo": every action that changes notes or chats can be taken back for a few seconds.
void showUndo(ScaffoldMessengerState m, String text, Future<void> Function() undo, VoidCallback? onUndone) {
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      action: SnackBarAction(label: 'Undo', onPressed: () async {
        HapticFeedback.selectionClick();
        await undo();
        onUndone?.call();
      }),
    ));
}
