import 'package:flutter/material.dart';

import 'app_services.dart';
import 'data/update_check.dart';
import 'features.dart';

/// The semi build: no counter, no blocker, no goals, no notifications, no installer. It asks Android for nothing but the internet.
class SemiFeatures extends AppFeatures {
  const SemiFeatures();

  @override
  String get flavor => 'semi';

  @override
  String get updateExplain => 'This opens the release page on GitHub, where you download the APK.';

  @override
  String get updateAction => 'Open page';

  @override
  Future<void> installUpdate(BuildContext context, AppServices s, UpdateInfo info) =>
      s.bridge.openUrl('https://github.com/nevil-sanish/reel-analyser/releases/tag/${info.tag}');
}
