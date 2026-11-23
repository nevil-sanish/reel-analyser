import 'package:flutter/material.dart';

/// The opt-in to reading the reel screens, asked in the app itself. The counter and the Reel blocker work only after "Allow";
/// until then the Accessibility service reads nothing, even if Android has it switched on.
Future<bool> askDetectionConsent(BuildContext context, {bool forSites = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Allow reading the screens?'),
      content: Text(
        forSites
            ? 'To block websites with Accessibility, Reel Analyser reads one thing: the address bar of your browser, to see which website is open. '
                'It reads nothing else on the page, never takes screenshots and never records your screen. Nothing is sent anywhere. '
                'You can turn it off here at any time.\n\n'
                'Warning: while Accessibility is on, payment and banking apps such as Google Pay may refuse to open or work. '
                'Reel Analyser never sees those apps, but they check whether any Accessibility service is on. '
                'Turn it off before you use them.'
            : 'To count reels and to block them past your limit, Reel Analyser must notice when a Reel or Short is on screen. '
        'It never takes screenshots and never records your screen. It reads only which parts of the Instagram, YouTube, Snapchat and TikTok '
        'screens are showing (and the browser address bar, if you block websites with Accessibility), and only while this is on. Nothing is sent anywhere. '
        'You can turn it off here at any time.\n\n'
        'Warning: while Accessibility is on, payment and banking apps such as Google Pay may refuse to open or work. '
        'Reel Analyser never sees those apps, but they check whether any Accessibility service is on. '
        'Turn it off before you use them.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  return ok == true;
}
