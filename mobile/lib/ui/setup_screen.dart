import 'package:flutter/material.dart';

import '../app_services.dart';
import '../flavor.dart';
import '../native/counter_bridge.dart';
import 'liquid.dart';

/// Insights setup. Both parts are optional: Usage access for time in the apps, Accessibility for reel counts.
/// Re-checked whenever you come back from a system screen.
class SetupScreen extends StatefulWidget {
  final AppServices services;
  const SetupScreen(this.services, {super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  CounterBridge get b => widget.services.bridge;
  CounterStatus? _s;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final s = await b.status();
    if (mounted) setState(() => _s = s);
  }

  /// Prominent disclosure (Google Play policy): what the access reads and what is done with it, asked before the
  /// system screen opens. The system screen is only opened after "Agree".
  static const _disclosures = {
    'openUsageAccess': ('Usage access',
        'Reel Analyser will read Android\'s app-usage statistics to show how long you spend in Instagram and YouTube, '
            'by day and hour. Nothing is read from the screen. The figures stay on this phone, are deleted after 90 days, and are '
            'never sent anywhere. You can turn this off in Android settings at any time.'),
    'openAccessibilitySettings': ('Accessibility service',
        'Reel Analyser will use Android\'s Accessibility service to notice when you are on an Instagram or YouTube Reels or '
            'Shorts screen, so it can count them and the time on them. It reads only those two apps, ignores every other app, '
            'never types, taps or scrolls, and keeps only an anonymous fingerprint and a count on this phone, deleted after 90 days. '
            'Nothing is sent anywhere. You can turn it off in Android settings at any time.'),
  };

  Future<void> _go(String screen) async {
    final d = _disclosures[screen];
    if (d != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(d.$1),
          content: Text(d.$2),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Agree')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await b.open(screen);
  }

  Widget _step(String title, String detail, bool? done, String screen, String button) => ListTile(
        leading: Icon(done == true ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done == true ? Colors.green : null),
        title: Text(title),
        subtitle: Text(detail),
        trailing: done == true ? null : FilledButton.tonal(onPressed: () => _go(screen), child: Text(button)),
      );

  Widget _header(BuildContext context, String title, String detail) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return LiquidScaffold(
      appBar: AppBar(title: const Text('Set up Insights')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (s.sdkInt >= 33)
                  _step('Allow notifications', 'For "note ready", the evening digest and the alert when counting breaks.',
                      s.notificationsAllowed, 'openNotificationSettings', 'Open'),
                _header(context, 'Optional: time in Instagram and YouTube',
                    'Insights are optional. Notes and chat work without any of this.'),
                _step('Allow usage access', 'Time spent in each app, from Android\'s own app usage. '
                    'Nothing is read from the screen.', s.usageAccess, 'openUsageAccess', 'Open'),
                if (!kPrivateBuild) ...[
                _header(context, 'Optional: count reels and Shorts',
                    'Turn this on to also see how many reels and Shorts you watch, and the time on those screens.'),
                if (s.sdkInt >= 33 && !s.serviceEnabled)
                  _step('Allow restricted settings', 'Android blocks Accessibility for apps installed from a file. '
                      'In App info, tap ⋮ → Allow restricted settings.', null, 'openAppInfo', 'App info'),
                _step('Turn on Reel Analyser in Accessibility', 'Installed apps → Reel Analyser → On. It only reads the Reels and '
                    'Shorts screens, and never taps or scrolls.', s.serviceEnabled, 'openAccessibilitySettings', 'Open'),
                _step('Battery: unrestricted', 'So Android doesn\'t stop the counter in the background.', s.batteryExempt,
                    'requestBatteryExemption', 'Allow'),
                if (s.needsAutostart)
                  _step('Allow Autostart', '${s.manufacturer} phones stop background apps unless Autostart is on.', null,
                      'openAutostart', 'Open'),
                ],
                if (s.serviceEnabled && !s.serviceRunning)
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Accessibility is on but the counter isn\'t running yet. Turn it off and on again if this stays.'),
                  ),
              ],
            ),
    );
  }
}
