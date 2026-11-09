import 'package:flutter/material.dart';

import 'liquid.dart';
import 'motion.dart';

/// A titled card with a Greek key under the title, rising into place: the building block of Settings and About.
class SectionCard extends StatelessWidget {
  final int index;
  final String title;
  final List<Widget> children;
  const SectionCard({required this.index, required this.title, required this.children, super.key});

  @override
  Widget build(BuildContext context) => Reveal(
        index: index,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const MeanderDivider(height: 7, opacity: 0.55),
                  const SizedBox(height: 12),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      );
}
