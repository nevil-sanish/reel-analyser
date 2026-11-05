import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../core/models.dart';

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
    return Scaffold(
      appBar: AppBar(
        actions: [
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
              await services.library.delete(reel.url);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText(reel.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text([if (reel.author.isNotEmpty) '@${reel.author}', reel.app].join(' · '), style: t.bodySmall),
          if (reel.analysis != 'done') ...[
            const SizedBox(height: 8),
            Chip(
              avatar: const Icon(Icons.info_outline, size: 16),
              label: Text(reel.analysis == 'text-only'
                  ? 'From saved text only: the link never arrived or the reel couldn\'t be fetched'
                  : reel.app == 'instagram'
                      ? 'From caption + thumbnail: Instagram didn\'t hand over the video (best step ${reel.step})'
                      : 'From title + thumbnail: Gemini couldn\'t watch this video'),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(reel.summary, style: t.bodyLarge)),
          ),
          if (reel.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Key points', style: t.titleMedium),
            for (final k in reel.keyPoints)
              Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText('•  $k')),
          ],
          if (reel.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 6, children: [for (final tag in reel.tags) Chip(label: Text('#$tag'))]),
          ],
          if (reel.caption.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Original caption', style: t.titleSmall),
            SelectableText(reel.caption, style: t.bodySmall),
          ],
          const SizedBox(height: 16),
          SelectableText(reel.url, style: t.bodySmall),
        ],
      ),
    );
  }
}
