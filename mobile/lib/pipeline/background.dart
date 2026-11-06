import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../app_services.dart';
import '../native/counter_bridge.dart';
import 'runner.dart';

/// WM-ANALYSE: runs in a background engine, without the UI.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final s = await AppServices.create();
    // No library.close(): sqflite shares one native connection per path across engines in the process,
    // so closing it here also closed the open app's database (every screen then failed with database_closed).
    await analyseAndNotify(s.runner, s.bridge);
    return true;
  });
}

/// The task's work once the stores are open; T-BG-01 runs it with fakes.
Future<void> analyseAndNotify(Runner runner, CounterBridge bridge) async {
  if (await runner.processQueue() == 0) return;
  // Only from the background: with the app open, the library already shows the new notes.
  final t = runner.finishedTitles;
  await bridge.notifyNotes(
    t.length == 1 ? 'Note ready' : '${t.length} notes ready',
    t.length == 1 ? t.single : t.take(3).join(' · '),
  );
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
