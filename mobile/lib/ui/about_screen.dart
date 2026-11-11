import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../core/distribution.dart';
import 'developer_card.dart';
import 'legal_screen.dart';
import 'liquid.dart';
import 'section_card.dart';
import 'theme.dart';
import 'update_flow.dart';

/// The developer's Buy Me a Coffee page. Opened in the browser; the app sends nothing itself.
const buyMeACoffee = 'https://buymeacoffee.com/nevilsanish';

/// The developer's UPI ID. The button opens the person's UPI app; they choose the amount there.
const upiId = 'nevilsanish@oksbi';
final upiLink = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent('Nevil Sanish')}&cu=INR&tn=${Uri.encodeComponent('Support Reel Analyser')}';

/// The About tab: who made the app, feedback, updates, and every legal text. In both builds.
class AboutScreen extends StatelessWidget {
  final AppServices services;
  const AboutScreen(this.services, {super.key});

  /// The one thing that leaves the phone on purpose: what you type here, as a GitHub issue you submit yourself.
  Future<void> _feedback(BuildContext context) async {
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send feedback'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: text, maxLines: 5, autofocus: true, decoration: const InputDecoration(hintText: 'What works, what doesn\'t?')),
            const SizedBox(height: 8),
            const Text('Opens a GitHub issue with only this text and the app version. You review it before it\'s posted.', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true || text.text.trim().isEmpty) return;
    final body = Uri.encodeQueryComponent('${text.text.trim()}\n\n— Reel Analyser ${AppServices.version}');
    await services.bridge.openUrl('https://github.com/nevil-sanish/reel-analyser/issues/new?title=Feedback&body=$body');
  }

  Widget _link(BuildContext context, IconData icon, String title, VoidCallback onTap, {String? subtitle}) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    return LiquidScaffold(
      background: false,
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          SectionCard(index: 0, title: 'About the developer', children: [DeveloperCard(onOpen: services.bridge.openUrl)]),
          SectionCard(index: 1, title: 'Feedback', children: [
            const Text('Found a bug or have an idea?'),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: () => _feedback(context), icon: const Icon(Icons.feedback_outlined), label: const Text('Send feedback')),
          ]),
          SectionCard(index: 2, title: 'Support the app', children: [
            const _FreeForever(),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => services.bridge.openUrl(buyMeACoffee),
                  icon: const Icon(Icons.local_cafe_rounded),
                  label: const Text('Buy a coffee'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (await services.bridge.openUrl(upiLink)) return;
                    await Clipboard.setData(const ClipboardData(text: upiId));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No UPI app found. UPI ID $upiId copied.')));
                    }
                  },
                  icon: const Icon(Icons.currency_rupee_rounded),
                  label: const Text('UPI'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  await Clipboard.setData(const ClipboardData(text: upiId));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UPI ID copied')));
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text('UPI ID: $upiId  ·  tap to copy', style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => open(LegalScreen.support),
                child: const Text('Refunds within 7 days · Support and Refund Policy'),
              ),
            ),
          ]),
          SectionCard(index: 3, title: 'About and legal', children: [
            if (fromFdroid)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.system_update_outlined),
                title: const Text('Updates come from F-Droid'),
                subtitle: Text('You have ${AppServices.version}'),
              )
            else
              _link(context, Icons.system_update_outlined, 'Check for updates', () => checkForUpdate(context, services), subtitle: 'You have ${AppServices.version}'),
            _link(context, Icons.privacy_tip_outlined, 'Privacy Policy', () => open(LegalScreen.privacy)),
            _link(context, Icons.gavel_outlined, 'Terms of Use', () => open(LegalScreen.terms)),
            _link(context, Icons.info_outline, 'Disclaimer', () => open(LegalScreen.disclaimer)),
            _link(context, Icons.receipt_long_outlined, 'Support and Refund Policy', () => open(LegalScreen.support)),
            _link(context, Icons.article_outlined, 'Open-source licenses',
                () => showLicensePage(context: context, applicationName: 'Reel Analyser', applicationVersion: AppServices.version)),
          ]),
          Center(child: Text('Reel Analyser ${AppServices.version}', style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// The promise first: free forever. Support only helps future work.
class _FreeForever extends StatelessWidget {
  const _FreeForever();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: dark ? const Color(0xFF2A2412) : Brand.goldPale,
        border: Border.all(color: Brand.gold.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(gradient: Brand.gradient, shape: BoxShape.circle),
          child: const Icon(Icons.favorite_rounded, size: 18, color: Brand.onGold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Free, always', style: Brand.serif(t.textTheme.titleMedium, size: 20, weight: 700)),
            const SizedBox(height: 4),
            Text(
              'Reel Analyser is free and will always stay free to use, with no ads and no tracking. '
              'Support is entirely optional: it only helps the developer keep improving this app and build more apps like it in the future.',
              style: t.textTheme.bodyMedium,
            ),
          ]),
        ),
      ]),
    );
  }
}
