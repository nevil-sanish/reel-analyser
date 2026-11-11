import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/models.dart';
import '../data/folders.dart';
import 'motion.dart';

/// Asks for a folder name. Null when cancelled.
Future<String?> askFolderName(BuildContext context, {String title = 'New folder', String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'For example: Cooking, Python, Fitness'),
        onSubmitted: (v) => Navigator.pop(d, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

void _say(BuildContext context, String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

/// Makes a folder and fills it with the notes whose words clearly match its name. Returns its id.
Future<int?> createFolder(BuildContext context, AppServices s) async {
  final name = await askFolderName(context);
  if (name == null || name.isEmpty || !context.mounted) return null;
  final id = await s.library.addFolder(name, DateTime.now().millisecondsSinceEpoch);
  if (!context.mounted) return null;
  if (id == null) {
    _say(context, name.toLowerCase() == 'all' ? '"All" is always there.' : 'There is already a folder called "$name".');
    return null;
  }
  final of = await s.library.folderOf();
  final f = Folder(id, name);
  final moved = {
    for (final r in await s.library.reels())
      if (!of.containsKey(r.url) && matchFolder(r, [f]) == id) r.url: id,
  };
  await s.library.setFolders(moved);
  if (context.mounted) {
    _say(context, moved.isEmpty ? 'Folder "$name" made. Press Organize to sort your notes into it.' : 'Folder "$name" made with ${moved.length} matching notes.');
  }
  return id;
}

/// Rename or delete a folder (its notes stay in All).
Future<void> manageFolder(BuildContext context, AppServices s, Folder f, VoidCallback onDone) async {
  final pick = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.edit_outlined), title: Text('Rename "${f.name}"'), onTap: () => Navigator.pop(c, 'rename')),
        ListTile(
          leading: const Icon(Icons.folder_delete_outlined),
          title: const Text('Delete folder'),
          subtitle: const Text('Its notes stay in All. Its chat is deleted.'),
          onTap: () => Navigator.pop(c, 'delete'),
        ),
      ]),
    ),
  );
  if (!context.mounted) return;
  if (pick == 'rename') {
    final n = await askFolderName(context, title: 'Rename folder', initial: f.name);
    if (n == null || n.isEmpty || !context.mounted) return;
    if (!await s.library.renameFolder(f.id, n) && context.mounted) _say(context, 'There is already a folder called "$n".');
  } else if (pick == 'delete') {
    Haptics.heavy();
    await s.library.deleteFolder(f.id);
  }
  onDone();
}

/// "Move to folder" for selected notes. Returns true when something moved.
Future<bool> moveToFolder(BuildContext context, AppServices s, List<Reel> notes) async {
  final folders = await s.library.folders();
  if (!context.mounted) return false;
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Move ${notes.length == 1 ? '1 note' : '${notes.length} notes'} to', style: Theme.of(c).textTheme.titleMedium),
        ),
        ListTile(leading: const Icon(Icons.all_inbox_outlined), title: const Text('All only (no folder)'), onTap: () => Navigator.pop(c, 0)),
        for (final f in folders)
          ListTile(leading: const Icon(Icons.folder_outlined), title: Text(f.name), onTap: () => Navigator.pop(c, f.id)),
        ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: const Text('New folder…'), onTap: () => Navigator.pop(c, -1)),
      ]),
    ),
  );
  if (picked == null || !context.mounted) return false;
  var id = picked == 0 ? null : picked;
  if (picked == -1) {
    final name = await askFolderName(context);
    if (name == null || name.isEmpty || !context.mounted) return false;
    id = await s.library.addFolder(name, DateTime.now().millisecondsSinceEpoch);
    if (id == null) {
      if (context.mounted) _say(context, 'There is already a folder called "$name".');
      return false;
    }
  }
  await s.library.setFolders({for (final r in notes) r.url: id});
  Haptics.medium();
  return true;
}

/// Organize: the AI sorts every note into the person's folders first, then suggests new folders for real topics, which they
/// approve. Notes that fit nothing stay in All only.
Future<void> organize(BuildContext context, AppServices s, VoidCallback onDone) async {
  if ((await s.chatProviders()).isEmpty) {
    if (context.mounted) _say(context, 'Add an AI key in Settings first: Organize uses it.');
    return;
  }
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.auto_awesome_rounded),
      title: const Text('Organize your notes?'),
      content: const Text('Your AI sorts every note into your folders first. For a real topic shared by at least $minSuggested notes '
          'it may suggest a new folder, which you can accept or skip. Notes that fit nothing stay in All.\n\n'
          'The title, tags and first line of each note are sent to your own AI provider. Nothing else.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Organize')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Expanded(child: Text('Sorting your notes…'))]),
    ),
  );
  OrganizePlan? plan;
  Object? error;
  try {
    plan = await s.organize();
  } on Object catch (e) {
    error = e;
  }
  nav.pop();
  if (!context.mounted) return;
  if (plan == null) return _say(context, 'Could not organize right now: $error');
  final sorted = plan.assign.values.where((v) => v != null).length;
  final suggestions = plan.suggestions();
  final all = {for (final r in await s.library.reels()) r.url: r};
  if (!context.mounted) return;
  final accepted = suggestions.isEmpty ? const <String>{} : await _approve(context, suggestions, all);
  final updates = <String, int?>{...plan.assign};
  var made = 0;
  for (final (name, urls) in suggestions) {
    if (!accepted.contains(name)) continue;
    final id = await s.library.addFolder(name, DateTime.now().millisecondsSinceEpoch);
    if (id == null) continue;
    made++;
    for (final u in urls) {
      updates[u] = id;
    }
  }
  await s.library.setFolders(updates);
  onDone();
  if (context.mounted) {
    Haptics.success();
    _say(context, 'Sorted $sorted ${sorted == 1 ? 'note' : 'notes'} into your folders'
        '${made == 0 ? '' : ', and made $made new ${made == 1 ? 'folder' : 'folders'}'}. The rest are in All.');
  }
}

/// The suggested new folders, each with its notes; returns the names the person ticked.
Future<Set<String>> _approve(BuildContext context, List<(String, List<String>)> suggestions, Map<String, Reel> notes) async {
  final ticked = {for (final (n, _) in suggestions) n};
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text('New folders suggested', style: Theme.of(c).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Topics you have no folder for yet. Untick any you don\'t want: those notes stay in All.',
                  style: Theme.of(c).textTheme.bodyMedium),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final (name, urls) in suggestions)
                  CheckboxListTile(
                    value: ticked.contains(name),
                    onChanged: (v) => set(() => v == true ? ticked.add(name) : ticked.remove(name)),
                    title: Text('$name · ${urls.length} notes'),
                    subtitle: Text(urls.take(3).map((u) => notes[u]?.title ?? '').where((t) => t.isNotEmpty).join(' · '),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(children: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Skip all')),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create ticked')),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
  return ok == true ? ticked : const {};
}
