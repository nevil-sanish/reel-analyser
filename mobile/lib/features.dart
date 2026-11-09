import 'package:flutter/material.dart';

import 'app_services.dart';
import 'data/update_check.dart';

/// One tab of the bottom bar.
class AppTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// [active] is true while the tab is the one on screen, so a tab can reload when it comes back.
  final Widget Function(AppServices services, bool active) build;
  const AppTab(this.icon, this.activeIcon, this.label, this.build);
}

/// What the build adds to the app. The shared code asks this object and never imports a full-only file, so each APK
/// contains only its own features: the semi build is compiled from `main_semi.dart` and cannot reach anything in `lib/full/`
/// (a test follows the imports and fails if it could).
abstract class AppFeatures {
  const AppFeatures();

  /// `full` or `semi`: which APK of a release this build takes when it updates itself.
  String get flavor;

  /// Tabs between Ask and Library (Insights), and between Library and About (the blocker).
  List<AppTab> get afterAsk => const [];
  List<AppTab> get beforeAbout => const [];

  /// The strip under the Ask heading (today's reels). [openInsights] jumps to the Insights tab.
  Widget? askStrip(AppServices s, VoidCallback openInsights) => null;

  /// Extra Settings sections, in the same card style as the rest.
  List<Widget> settingsSections(BuildContext context, AppServices s, Widget Function(String title, List<Widget> children) section) => const [];

  /// The app was opened or came back to the front.
  Future<void> onOpen(AppServices s) async {}

  /// The background task ran (about every 15 minutes, and at midnight).
  Future<void> inBackground(AppServices s) async {}

  /// "Note ready" after a background run. The semi build posts no notifications.
  Future<void> notifyNotes(AppServices s, String title, String text) async {}

  /// Settings → Erase all my data, for what only this build keeps.
  Future<void> erase(AppServices s) async {}

  /// The Update button: the full build downloads and installs; the semi build opens the release page.
  String get updateExplain;
  String get updateAction;
  Future<void> installUpdate(BuildContext context, AppServices s, UpdateInfo info);
}
