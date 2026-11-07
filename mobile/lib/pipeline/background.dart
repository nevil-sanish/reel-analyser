import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../app_services.dart';
import '../flavor.dart';
import '../native/counter_bridge.dart';
import 'runner.dart';

/// WM-ANALYSE: runs in a background engine, without the UI.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final s = await AppServices.create();
      // No library.close(): sqflite shares one native connection per path across engines in the process,
      // so closing it here also closed the open app's database (every screen then failed with database_closed).
      final done = await analyseAndNotify(s.runner, s.bridge);
      debugPrint('ReelBot background "$task": ${done ? 'done' : 'failed'}${s.runner.lastProblem == null ? '' : ' (${s.runner.lastProblem})'}');
      return done;
    } on Object catch (e, st) {
      debugPrint('ReelBot background "$task" failed: $e\n$st');
      return false;
    }
  });
}

/// The task's work once the stores are open; T-BG-01 runs it with fakes.
Future<bool> analyseAndNotify(
  Runner runner,
  CounterBridge bridge, {
  Duration patience = const Duration(seconds: 150),
  Duration poll = const Duration(seconds: 5),
}) async {
  var n = await runner.processQueue();
  // Another run holds the queue: the open app (it finishes the queue itself) or one that was killed (its lock runs out
  // within 90 s). Wait for the lock instead of giving up: a retry would come minutes later, and later every time.
  for (var waited = Duration.zero; n == 0 && runner.lockBusy && waited < patience; waited += poll) {
    await Future<void>.delayed(poll);
    n = await runner.processQueue();
  }
  if (n == 0) return true;
  if (kPrivateBuild) return true; // the private build posts no notifications
  // Only from the background: with the app open, the library already shows the new notes.
  final t = runner.finishedTitles;
  await bridge.notifyNotes(
    t.length == 1 ? 'Note ready' : '${t.length} notes ready',
    t.length == 1 ? t.single : t.take(3).join(' · '),
  );
  return true;
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
