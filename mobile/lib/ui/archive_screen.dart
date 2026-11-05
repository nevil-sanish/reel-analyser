import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/models.dart';
import 'library_screen.dart';
import 'reel_screen.dart';

/// Seen notes older than 3 days. Still searchable, still used by the chat; restore one from its note.
class ArchiveScreen extends StatefulWidget {
  final AppServices services;
  const ArchiveScreen(this.services, {super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<Reel> _reels = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.services.library.reels(query: _query, archived: true);
    if (mounted) setState(() => _reels = r);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Archive')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SearchBar(
            hintText: 'Search the archive',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (q) {
              _query = q;
              _load();
            },
          ),
          const SizedBox(height: 12),
          if (_reels.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Text('Notes you\'ve read move here 3 days after you saved them.',
                  textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
          for (final r in _reels)
            SwipeNote(widget.services, r, onChanged: _load, onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ReelScreen(widget.services, r)));
              _load();
            }),
        ],
      ),
    );
  }
}
