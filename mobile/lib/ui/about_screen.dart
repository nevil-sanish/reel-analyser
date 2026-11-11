import 'package:flutter/material.dart';

import '../app_services.dart';
import 'developer_card.dart';
import 'legal_screen.dart';
import 'liquid.dart';
import 'section_card.dart';
import 'update_flow.dart';

/// The developer's Buy Me a Coffee page. Opened in the browser; the app sends nothing itself.
const buyMeACoffee = 'https://buymeacoffee.com/nevilsanish';

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
            const Text('Reel Analyser is free, with no ads and no tracking. If it helps you, you can buy the developer a coffee.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => services.bridge.openUrl(buyMeACoffee),
              icon: const Icon(Icons.local_cafe_rounded),
              label: const Text('Buy me a coffee'),
            ),
          ]),
          SectionCard(index: 3, title: 'About and legal', children: [
            _link(context, Icons.system_update_outlined, 'Check for updates', () => checkForUpdate(context, services), subtitle: 'You have ${AppServices.version}'),
            _link(context, Icons.privacy_tip_outlined, 'Privacy Policy', () => open(LegalScreen.privacy)),
            _link(context, Icons.gavel_outlined, 'Terms of Use', () => open(LegalScreen.terms)),
            _link(context, Icons.info_outline, 'Disclaimer', () => open(LegalScreen.disclaimer)),
            _link(context, Icons.article_outlined, 'Open-source licenses',
                () => showLicensePage(context: context, applicationName: 'Reel Analyser', applicationVersion: AppServices.version)),
          ]),
          Center(child: Text('Reel Analyser ${AppServices.version}', style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
