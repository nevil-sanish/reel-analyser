import 'package:flutter/material.dart';

import 'theme.dart';

/// First-run intro: three pages, each sliding and fading in, then into the app.
class IntroScreen extends StatefulWidget {
  final VoidCallback onDone;
  const IntroScreen({required this.onDone, super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pages = PageController();
  var _page = 0;

  static const _slides = [
    (Icons.ios_share_rounded, 'Share a reel, get a note', 'In Instagram or YouTube, tap Share → Reel Bot. It turns the reel into a short summary with key points.'),
    (Icons.insights_rounded, 'See how much you scroll', 'Reel Bot counts the reels and shorts you watch each day. It never records which ones.'),
    (Icons.lock_rounded, 'Yours, on your phone', 'No account and no server. Notes stay on this phone; only a reel you share goes to the AI, with your own key.'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(onPressed: widget.onDone, child: const Text('Skip')),
            ),
            const SizedBox(height: 12),
            const BrandMark(size: 104),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _Slide(_slides[i], active: i == _page),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? t.colorScheme.primary : t.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: last
                      ? widget.onDone
                      : () => _pages.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic),
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  final (IconData, String, String) slide;
  final bool active;
  const _Slide(this.slide, {required this.active});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AnimatedSlide(
      offset: active ? Offset.zero : const Offset(0, 0.08),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: const Duration(milliseconds: 500),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(slide.$1, size: 40, color: t.colorScheme.tertiary),
              const SizedBox(height: 16),
              Text(slide.$2, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(slide.$3, style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
