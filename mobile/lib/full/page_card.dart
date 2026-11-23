import 'package:flutter/material.dart';

import '../ui/liquid.dart';
import '../ui/motion.dart';

/// The card of the Blocker pages: an icon and a title with a Greek key under it, rising into place. Pages use it for each section.
class PageCard extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final int index;
  const PageCard({this.icon, required this.title, this.subtitle, required this.children, this.index = 0, super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Reveal(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (icon != null) ...[Icon(icon, color: t.colorScheme.primary, size: 22), const SizedBox(width: 10)],
                  Expanded(child: Text(title, style: t.textTheme.titleLarge)),
                ]),
                const SizedBox(height: 4),
                const MeanderDivider(height: 7, opacity: 0.55),
                if (subtitle != null) ...[
                  const SizedBox(height: 10),
                  Text(subtitle!, style: t.textTheme.bodySmall),
                ],
                const SizedBox(height: 10),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
