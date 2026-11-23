import 'package:flutter/material.dart';

import 'liquid.dart';
import 'motion.dart';

/// What every screen shows while its data loads: grey-gold shapes where the cards and text will be, with a light sweeping across,
/// so the page keeps its layout and never flashes empty or jumps when the real content arrives.
class SkeletonCards extends StatelessWidget {
  final int count;
  const SkeletonCards({this.count = 4, super.key});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    children: [for (var i = 0; i < count; i++) const SkeletonCard()],
  );
}

/// One card-shaped placeholder: a badge and a name, a title, two lines of text.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 14),
    child: Glass(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Skeleton(width: 28, height: 28, radius: 8),
              SizedBox(width: 10),
              Expanded(child: Skeleton(height: 14)),
              SizedBox(width: 40),
            ],
          ),
          SizedBox(height: 16),
          Skeleton(height: 20, width: 220),
          SizedBox(height: 12),
          Skeleton(height: 13),
          SizedBox(height: 8),
          Skeleton(height: 13, width: 260),
        ],
      ),
    ),
  );
}

/// Lines of text, for a document that is still loading.
class SkeletonText extends StatelessWidget {
  final int lines;
  const SkeletonText({this.lines = 14, super.key});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    children: [
      const Skeleton(height: 26, width: 200),
      const SizedBox(height: 18),
      for (var i = 0; i < lines; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Skeleton(height: 13, width: i % 5 == 4 ? 160 : null),
        ),
    ],
  );
}
