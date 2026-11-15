import 'package:flutter/material.dart';

/// The opt-in to reading the reel screens, asked in the app itself. The counter and the Reel blocker work only after "Allow";
/// until then the Accessibility service reads nothing, even if Android has it switched on.
///
/// [limits]: asked from Apps & sites, with words about apps and websites instead of reels.
Future<bool> askDetectionConsent(BuildContext context, {bool limits = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(limits ? 'Allow the time limits to work?' : 'Allow reading the screens?'),
      content: Text(
        limits
            ? 'To block an app or website when its time is used up, Reel Analyser must notice which app is in front, and in a browser read the '
                'address bar, only for the apps and sites you add. The time in an app comes from Android\'s Usage access. '
                'It reads nothing else inside apps or pages, never takes screenshots, never records your screen, and sends nothing anywhere. '
                'You can turn it off at any time.'
            : 'To count reels and to block them past your limit, Reel Analyser must notice when a Reel or Short is on screen. '
                'It never takes screenshots and never records your screen. It reads only which parts of the Instagram and YouTube '
                'screens are showing, and only while this is on. Nothing is sent anywhere. '
                'You can turn it off here at any time.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Allow')),
      ],
    ),
  );
  return ok == true;
}
