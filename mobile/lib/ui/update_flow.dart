import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/update_check.dart';

/// About: look for a newer release now and offer it.
Future<void> checkForUpdate(BuildContext context, AppServices s) async {
  final m = ScaffoldMessenger.of(context);
  m.showSnackBar(const SnackBar(content: Text('Checking for updates…')));
  final info = await latestUpdate(s.client, AppServices.version, semi: s.features.flavor == 'semi');
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
      content: Text(s.features.updateExplain),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.features.updateAction)),
      ],
    ),
  );
  if (go == true && context.mounted) await s.features.installUpdate(context, s, info);
}
