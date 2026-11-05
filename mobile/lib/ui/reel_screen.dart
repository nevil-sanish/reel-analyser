import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../core/models.dart';
import 'liquid.dart';

class ReelScreen extends StatefulWidget {
  final AppServices services;
  final Reel reel;
  const ReelScreen(this.services, this.reel, {super.key});

  @override
  State<ReelScreen> createState() => _ReelScreenState();
}

class _ReelScreenState extends State<ReelScreen> {
  AppServices get services => widget.services;
  Reel get reel => widget.reel;

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
            tooltip: reel.archived ? 'Move back to library' : 'Archive',
            icon: Icon(reel.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
            onPressed: () async {
              HapticFeedback.mediumImpact();
              await services.library.setArchived(reel.url, !reel.archived);
              if (context.mounted) Navigator.pop(context);
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
              HapticFeedback.heavyImpact();
              await services.library.delete(reel.url);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (reel.app == 'photo') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(File(reel.url.substring('photo:'.length)),
                  width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            ),
            const SizedBox(height: 16),
          ],
          SelectableText(reel.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text([if (reel.author.isNotEmpty) '@${reel.author}', reel.app, savedOn(reel.savedAt)].join(' · '), style: t.bodySmall),
          if (reel.analysis != 'done') ...[
            const SizedBox(height: 8),
            // Short label; the long reason is a tooltip, for when a fallback needs reporting.
            Tooltip(
              message: reel.analysis == 'text-only'
                  ? 'The link never arrived or the reel couldn\'t be fetched'
                  : reel.app == 'instagram'
                      ? 'Instagram didn\'t hand over the video (best step ${reel.step})'
                      : 'Gemini couldn\'t watch this video',
              child: Chip(
                avatar: const Icon(Icons.info_outline, size: 16),
                label: Text(reel.analysis == 'text-only' ? 'From text only' : 'From caption + thumbnail'),
              ),
            ),
          ],
          if (reel.analysis != 'done' && !reel.url.startsWith('local:'))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Try again with the video'),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final ok = await services.retry(reel);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok ? 'Queued again. It will be analysed shortly.' : 'Share the reel to Reel Bot again to retry.')));
                  if (ok) Navigator.pop(context);
                },
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(reel.summary, style: t.bodyLarge)),
          ),
          // Just the gist: older notes may hold more points, the screen shows three.
          for (final k in reel.keyPoints.take(3))
            Padding(padding: const EdgeInsets.only(top: 10), child: SelectableText('•  $k', style: t.bodyLarge)),
          if (reel.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              for (final tag in reel.tags.take(3)) Text('#$tag', style: t.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ]),
          ],
        ],
      ),
    );
  }
}
