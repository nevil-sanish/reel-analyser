import 'package:flutter/material.dart';

/// Who made the app, and who helped. Shown in Settings.
class Developer {
  static const name = 'Nevil Mathew Sanish';
  static const github = 'https://github.com/nevil-sanish';
  static const githubName = 'github.com/nevil-sanish';
  static const about =
      'I build Reel Analyser on my own. It turns the Reels, Shorts and photos you share into short notes you can search '
      'and chat with, and, in the full version, can help you limit how much you watch. There is no account and no server: '
      'your notes stay on your phone and you use your own AI keys. It is free and open source (MIT).';
  static const thanksTo = ['Sanjay S', 'Ashin Antony', 'Harry SP'];
  static const thanks =
      'Thank you to Sanjay S, Ashin Antony and Harry SP for helping, suggesting and contributing.';
}

class DeveloperCard extends StatelessWidget {
  /// Opens the link outside the app.
  final void Function(String url) onOpen;
  const DeveloperCard({required this.onOpen, super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Developer.name,
          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          'Developer',
          style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Text(Developer.about, style: t.bodyMedium?.copyWith(height: 1.4)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.code_rounded),
          title: const Text('GitHub'),
          subtitle: const Text(Developer.githubName),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => onOpen(Developer.github),
        ),
        const Divider(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.favorite_rounded, size: 18, color: c.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                Developer.thanks,
                style: t.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
