import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../app_services.dart';

/// WM-ANALYSE: runs in a background engine, without the UI.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final s = await AppServices.create();
    try {
      if (await s.runner.processQueue() > 0) {
        // Only from the background: with the app open, the library already shows the new notes.
        final t = s.runner.finishedTitles;
        await s.bridge.notifyNotes(
          t.length == 1 ? 'Note ready' : '${t.length} notes ready',
          t.length == 1 ? t.single : t.take(3).join(' · '),
        );
      }
    } finally {
      await s.library.close();
    }
    return true;
  });
}

Future<void> scheduleBackgroundAnalysis() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'analyse',
    'analyse',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
