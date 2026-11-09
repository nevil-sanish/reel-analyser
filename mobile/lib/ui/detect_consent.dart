import 'package:flutter/material.dart';

/// The opt-in to reading the reel screens, asked in the app itself. The counter and the Reel blocker work only after "Allow";
/// until then the Accessibility service reads nothing, even if Android has it switched on.
Future<bool> askDetectionConsent(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Allow reading the reel screens?'),
      content: const Text(
        'To count reels and to block them past your limit, Reel Analyser must notice when a Reel or Short is on screen. '
        'It never takes screenshots and never records your screen. It reads only which parts of the Instagram and YouTube '
        'screens are showing (and, in a browser, the address bar), and only while this is on. Nothing is sent anywhere. '
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
