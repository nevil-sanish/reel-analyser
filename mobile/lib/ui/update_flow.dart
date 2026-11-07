import 'dart:io';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/update_check.dart';
import '../data/updater.dart';
import '../flavor.dart';

/// Update button: the full build downloads the APK, checks it and opens Android's installer; the semi build has no
/// install permission, so it opens that version's release page on GitHub.
Future<void> runUpdate(BuildContext context, AppServices s, UpdateInfo info) async {
  if (kSemiBuild) {
    await s.bridge.openUrl('https://github.com/nevil-sanish/reel-analyser/releases/tag/${info.tag}');
    return;
  }
  final progress = ValueNotifier<double>(0);
  final m = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Downloading ${info.tag}'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: v > 0 ? v : null, minHeight: 6),
            const SizedBox(height: 8),
            Text(v > 0 ? '${(v * 100).round()}%' : 'Starting…'),
          ]),
        ),
      ),
    ),
  );
  String? failure;
  try {
    final file = await downloadUpdate(s.client, info, Directory(await s.bridge.updateDir()), (v) => progress.value = v);
    final r = await s.bridge.installApk(file.path);
    if (r == 'needs_permission') {
      failure = 'Allow Reel Analyser to install apps in the screen that just opened, then press Update again.';
    } else if (r != 'started') {
      failure = 'Android would not open the installer (${r.replaceFirst('failed: ', '')}).';
    }
  } on Object catch (e) {
    failure = 'Update failed: $e';
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (failure != null) m.showSnackBar(SnackBar(content: Text(failure)));
}

/// Settings: look for a newer release now and offer it.
Future<void> checkForUpdate(BuildContext context, AppServices s) async {
  final m = ScaffoldMessenger.of(context);
  m.showSnackBar(const SnackBar(content: Text('Checking for updates…')));
  final info = await latestUpdate(s.client, AppServices.version);
  m.hideCurrentSnackBar();
  if (!context.mounted) return;
  if (info == null) {
    m.showSnackBar(const SnackBar(content: Text('You have the latest version.')));
    return;
  }
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Reel Analyser ${info.tag} is out'),
      content: Text(kSemiBuild ? 'This opens the release page on GitHub, where you download the APK.' : 'It is downloaded, checked against the release checksum, and handed to Android to install. Your notes and keys stay.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(kSemiBuild ? 'Open page' : 'Update')),
      ],
    ),
  );
  if (go == true && context.mounted) await runUpdate(context, s, info);
}
