import 'dart:io';

import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import '../app_services.dart';
import '../data/update_check.dart';
import '../features.dart';
import 'blocker.dart';
import 'blocker_tab.dart';
import 'debug_screen.dart';
import 'full_bridge.dart';
import 'goal_store.dart';
import 'goals.dart';
import 'insights_screen.dart';
import 'setup_screen.dart';
import 'today_strip.dart';
import 'updater.dart';

/// The goals' engine for this app's services: one per [AppServices], built on first use.
final _engines = Expando<GoalEngine>();
GoalEngine goalEngine(AppServices s) => _engines[s] ??= GoalEngine(
      storeFuture: GoalStore.of(s.library),
      fetcher: GoalFetcher(s.client),
      publish: (p, apps) => BlockerBridge().punishSet(until: p.until, apps: apps, streak: p.streak),
    );

/// The full build: the reel counter and Insights, the Reel blocker with Daily goals, notifications and the in-app updater.
class FullFeatures extends AppFeatures {
  const FullFeatures();

  @override
  String get flavor => 'full';

  @override
  List<AppTab> get afterAsk => const [AppTab(Icons.insights_outlined, Icons.insights, 'Insights', _insights)];

  @override
  List<AppTab> get beforeAbout => const [AppTab(Icons.shield_outlined, Icons.shield, 'Blocker', _blocker)];

  static Widget _insights(AppServices s, bool active) => InsightsScreen(s);
  static Widget _blocker(AppServices s, bool active) => BlockerTab(s, active: active);

  @override
  Widget? askStrip(AppServices s, VoidCallback openInsights) => TodayStrip(s, onTap: openInsights);

  @override
  List<Widget> settingsSections(BuildContext context, AppServices s, Widget Function(String, List<Widget>) section) => [
        section('Insights', [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.checklist_rounded),
            title: const Text('Set up Insights'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(s))),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Counter debug'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebugScreen(s))),
          ),
        ]),
      ];

  @override
  Future<void> onOpen(AppServices s) async {
    await FullBridge().markOpened();
    await _judgeDays(s);
    await _scheduleMidnight();
  }

  @override
  Future<void> inBackground(AppServices s) async {
    await _judgeDays(s);
    await _scheduleMidnight();
  }

  /// The check that runs by itself every day just after midnight: one task for the next 00:20, named by its day so that the one
  /// running now can book tomorrow's without cancelling itself. The 15-minute task and opening the app are the fallbacks.
  Future<void> _scheduleMidnight() async {
    try {
      final now = DateTime.now();
      final at = nextMidnightCheck(now);
      await Workmanager().registerOneOffTask(
        'goals-${dateOf(at)}',
        'goals-midnight',
        initialDelay: at.difference(now),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    } on Object catch (e) {
      debugPrint('Midnight check not scheduled: $e');
    }
  }

  /// Judges the days that have ended (Daily goals). A site that cannot be reached is simply tried again later.
  Future<void> _judgeDays(AppServices s) async {
    try {
      await goalEngine(s).run();
    } on Object catch (e) {
      debugPrint('Goals check failed: $e');
    }
  }

  @override
  Future<void> notifyNotes(AppServices s, String title, String text) => FullBridge().notifyNotes(title, text);

  @override
  Future<void> erase(AppServices s) async => (await GoalStore.of(s.library)).eraseAll();

  @override
  String get updateExplain => 'It is downloaded, checked against the release checksum, and handed to Android to install. Your notes and keys stay.';

  @override
  String get updateAction => 'Update';

  /// Downloads the APK, checks it and opens Android's installer.
  @override
  Future<void> installUpdate(BuildContext context, AppServices s, UpdateInfo info) async {
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
    var offerPage = false;
    try {
      final bridge = FullBridge();
      final file = await downloadUpdate(s.client, info, Directory(await bridge.updateDir()), (v) => progress.value = v);
      final r = await bridge.installApk(file.path);
      if (r == 'needs_permission') {
        failure = 'Allow Reel Analyser to install apps in the screen that just opened, then press Update again.';
      } else if (r != 'started') {
        failure = 'Android would not open the installer (${r.replaceFirst('failed: ', '')}).';
      }
    } on UpdateException catch (e) {
      failure = 'Update failed: $e';
      offerPage = true;
    } on Object catch (e) {
      debugPrint('Update download failed: $e');
      // Some mobile networks reset connections to GitHub's file host; the browser often still gets through.
      failure = 'Could not download ${info.tag}. Your network may be blocking GitHub downloads. Open the release page to download it in your browser.';
      offerPage = true;
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (failure != null) {
      m.showSnackBar(SnackBar(
        content: Text(failure),
        duration: Duration(seconds: offerPage ? 12 : 4),
        action: offerPage
            ? SnackBarAction(
                label: 'Open page',
                onPressed: () => s.bridge.openUrl('https://github.com/nevil-sanish/reel-analyser/releases/tag/${info.tag}'))
            : null,
      ));
    }
  }
}
