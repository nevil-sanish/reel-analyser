import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'liquid.dart';

/// The Privacy Policy, Terms of Use or Disclaimer, from the copy bundled in the app so it reads offline.
/// The same files are the public versions on GitHub (mobile/assets/legal/).
class LegalScreen extends StatelessWidget {
  final String title;
  final String asset;
  const LegalScreen({required this.title, required this.asset, super.key});

  static const privacy = LegalScreen(title: 'Privacy Policy', asset: 'assets/legal/privacy.md');
  static const terms = LegalScreen(title: 'Terms of Use', asset: 'assets/legal/terms.md');
  static const disclaimer = LegalScreen(title: 'Disclaimer', asset: 'assets/legal/disclaimer.md');

  /// Headings (#, ##), bullets (-) and paragraphs, with **bold** runs: all the two documents use.
  static List<Widget> render(BuildContext context, String md) {
    final t = Theme.of(context).textTheme;
    TextSpan runs(String s, TextStyle? base) {
      final parts = s.split('**');
      return TextSpan(style: base, children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null),
      ]);
    }

    return [
      for (final raw in md.split('\n'))
        if (raw.trim().isEmpty)
          const SizedBox(height: 8)
        else if (raw.startsWith('## '))
          Padding(padding: const EdgeInsets.only(top: 14, bottom: 4), child: Text(raw.substring(3), style: t.titleMedium))
        else if (raw.startsWith('# '))
          Text(raw.substring(2), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700))
        else if (raw.startsWith('- '))
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 3, bottom: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 7, right: 10), child: Icon(Icons.circle, size: 6)),
              Expanded(child: SelectableText.rich(runs(raw.substring(2), t.bodyMedium?.copyWith(height: 1.4)))),
            ]),
          )
        else
          SelectableText.rich(runs(raw, t.bodyMedium?.copyWith(height: 1.45))),
    ];
  }

  @override
  Widget build(BuildContext context) => LiquidScaffold(
        appBar: AppBar(title: Text(title)),
        body: FutureBuilder<String>(
          future: rootBundle.loadString(asset),
          builder: (context, snap) => snap.hasData
              ? ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: render(context, snap.data!))
              : const Center(child: CircularProgressIndicator()),
        ),
      );
}
