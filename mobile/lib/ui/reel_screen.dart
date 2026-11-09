import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../core/models.dart';
import 'library_screen.dart';
import 'liquid.dart';
import 'note_chat_screen.dart';
import 'motion.dart';
import 'theme.dart';
import 'web_screen.dart';

class ReelScreen extends StatefulWidget {
  final AppServices services;
  final Reel reel;

  /// Called after an Undo from this page's archive or delete, so the list behind it shows the note again.
  final VoidCallback? onChanged;
  const ReelScreen(this.services, this.reel, {this.onChanged, super.key});

  @override
  State<ReelScreen> createState() => _ReelScreenState();
}

class _ReelScreenState extends State<ReelScreen> {
  AppServices get services => widget.services;
  Reel get reel => widget.reel;
  bool _full = false;

  @override
  void initState() {
    super.initState();
    services.library.markSeen(reel.url, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return LiquidScaffold(
      appBar: AppBar(
        actions: [
          if (reel.app != 'photo' && isReelLink(reel.url))
            IconButton(
              tooltip: 'Open the link here',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => WebScreen(services, url: reel.url, title: reel.title)),
              ),
            ),
          if (reel.app != 'photo')
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.link),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: reel.url));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
              },
            ),
          IconButton(
            tooltip: 'Mark as unread',
            icon: const Icon(Icons.mark_email_unread_outlined),
            onPressed: () async {
              Haptics.select();
              final m = ScaffoldMessenger.of(context);
              await services.library.markUnseen(reel.url);
              if (context.mounted) Navigator.pop(context);
              showUndo(m, 'Marked unread', () => services.library.markSeen(reel.url, DateTime.now().millisecondsSinceEpoch), widget.onChanged);
            },
          ),
          IconButton(
            tooltip: reel.archived ? 'Move back to library' : 'Archive',
            icon: Icon(reel.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
            onPressed: () async {
              Haptics.medium();
              final m = ScaffoldMessenger.of(context);
              await services.library.setArchived(reel.url, !reel.archived);
              if (context.mounted) Navigator.pop(context);
              showUndo(m, reel.archived ? 'Note restored' : 'Note archived',
                  () => services.library.setArchived(reel.url, reel.archived), widget.onChanged);
            },
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete this note?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok != true) return;
              Haptics.heavy();
              if (!context.mounted) return;
              final m = ScaffoldMessenger.of(context);
              await services.library.delete(reel.url);
              if (context.mounted) Navigator.pop(context);
              showUndo(m, 'Note deleted', () => services.library.saveReel(reel), widget.onChanged);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (reel.app == 'photo') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(File(reel.url.substring('photo:'.length)),
                  width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            ),
            const SizedBox(height: 16),
          ],
          Reveal(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(reel.title, style: t.headlineSmall),
              const SizedBox(height: 10),
              const SizedBox(width: 120, child: MeanderDivider(height: 7, opacity: 0.6)),
            ]),
          ),
          const SizedBox(height: 16),
          // At a glance: the overview bullets carry every important point in short, simple lines.
          Reveal(index: 1, child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: reel.overview.isEmpty
                  ? SelectableText(reel.summary, style: t.bodyLarge?.copyWith(height: 1.45))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final o in reel.overview)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              margin: const EdgeInsets.only(top: 8, right: 12),
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
                            ),
                            Expanded(child: SelectableText(o, style: t.bodyLarge?.copyWith(height: 1.4))),
                          ]),
                        ),
                    ]),
            ),
          ),),
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              onPressed: () {
                Haptics.select();
                setState(() => _full = !_full);
              },
              icon: AnimatedRotation(turns: _full ? 0.5 : 0, duration: const Duration(milliseconds: 300), child: const Icon(Icons.expand_more_rounded)),
              label: Text(_full ? 'Hide full analysis' : 'Show full analysis'),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_full
                ? const SizedBox(width: double.infinity)
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (reel.overview.isNotEmpty) ...[
                      Text('In detail', style: t.titleMedium),
                      const SizedBox(height: 6),
                      SelectableText(reel.summary, style: t.bodyLarge?.copyWith(height: 1.45)),
                      const SizedBox(height: 18),
                    ],
                    if (reel.keyPoints.isNotEmpty) ...[
                      Text('Everything in it', style: t.titleMedium),
                      for (final (i, k) in reel.keyPoints.indexed)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: 28, child: Text('${i + 1}.', style: t.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
                            Expanded(child: SelectableText(k, style: t.bodyLarge?.copyWith(height: 1.4))),
                          ]),
                        ),
                      const SizedBox(height: 18),
                    ],
                    if (reel.mentions.isNotEmpty) ...[
                      Text('Mentioned', style: t.titleMedium),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [for (final m in reel.mentions) Chip(label: Text(m))]),
                      const SizedBox(height: 18),
                    ],
                    for (final (label, text) in [('Transcript', reel.transcript), ('On-screen text', reel.onScreenText), ('Caption', reel.caption)])
                      if (text.isNotEmpty) ...[
                        Text(label, style: t.titleMedium),
                        const SizedBox(height: 6),
                        SelectableText(text, style: t.bodyLarge?.copyWith(height: 1.45)),
                        const SizedBox(height: 18),
                      ],
                    if (reel.transcript.isEmpty && reel.analysis == 'done' && reel.app != 'photo')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text('No transcript saved. Notes made before v0.9.6 don\'t have one; Re-analyse below to get it.', style: t.bodySmall),
                      ),
                    if (reel.tags.isNotEmpty)
                      Wrap(spacing: 8, children: [
                        for (final tag in reel.tags) Text('#$tag', style: t.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
                      ]),
                    const SizedBox(height: 12),
                    Text([if (reel.author.isNotEmpty) '@${reel.author}', reel.app, savedOn(reel.savedAt)].join(' · '), style: t.bodySmall),
                    if (reel.analysis != 'done') ...[
                      const SizedBox(height: 8),
                      Text(
                        reel.analysis == 'text-only'
                            ? 'Made from text only: the link never arrived or the reel couldn\'t be fetched.'
                            : reel.app == 'instagram'
                                ? 'Made from the caption and thumbnail: Instagram didn\'t hand over the video (best step ${reel.step}).'
                                : 'Made from the title and thumbnail: Gemini couldn\'t watch this video.',
                        style: t.bodySmall,
                      ),
                    ],
                    if (!reel.url.startsWith('local:'))
                      TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(reel.analysis == 'done' ? 'Re-analyse' : 'Try again with the video'),
                        onPressed: () async {
                          Haptics.light();
                          final ok = await services.retry(reel);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok ? 'Queued again. It will be analysed shortly.' : 'Share it to Reel Analyser again to re-analyse.')));
                          if (ok) Navigator.pop(context);
                        },
                      ),
                  ]),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Chat about this note'),
            onPressed: () {
              Haptics.select();
              Navigator.push(context, MaterialPageRoute(builder: (_) => NoteChatScreen(services, reel)));
            },
          ),
        ],
      ),
    );
  }
}
