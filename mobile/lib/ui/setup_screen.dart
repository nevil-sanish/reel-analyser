import 'package:flutter/material.dart';

import '../app_services.dart';
import '../native/counter_bridge.dart';

/// The permissions the counter needs, re-checked whenever you come back from a system screen.
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

  Widget _step(String title, String detail, bool? done, String screen, String button) => ListTile(
        leading: Icon(done == true ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done == true ? Colors.green : null),
        title: Text(title),
        subtitle: Text(detail),
        trailing: done == true ? null : FilledButton.tonal(onPressed: () => b.open(screen), child: Text(button)),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up counting')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (s.sdkInt >= 33 && !s.serviceEnabled)
                  _step('Allow restricted settings', 'Android blocks Accessibility for apps installed from a file. '
                      'In App info, tap ⋮ → Allow restricted settings.', null, 'openAppInfo', 'App info'),
                _step('Turn on Reel Bot in Accessibility', 'Installed apps → Reel Bot → On. It only reads the Reels and '
                    'Shorts screens, and never taps or scrolls.', s.serviceEnabled, 'openAccessibilitySettings', 'Open'),
                if (s.sdkInt >= 33)
                  _step('Allow notifications', 'For the alert when counting breaks.', s.notificationsAllowed,
                      'openNotificationSettings', 'Open'),
                _step('Battery: unrestricted', 'So Android doesn\'t stop the counter in the background.', s.batteryExempt,
                    'requestBatteryExemption', 'Allow'),
                if (s.needsAutostart)
                  _step('Allow Autostart', '${s.manufacturer} phones stop background apps unless Autostart is on.', null,
                      'openAutostart', 'Open'),
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
