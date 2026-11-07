import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_services.dart';
import 'flavor.dart';
import 'data/update_check.dart';
import 'pipeline/background.dart';
import 'ui/chat_screen.dart';
import 'ui/intro_screen.dart';
import 'ui/legal_screen.dart';
import 'ui/library_screen.dart';
import 'ui/liquid.dart';
import 'ui/theme.dart';
import 'ui/insights_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  // None of these is worth a blank screen at launch if the phone refuses one: the app opens without it.
  for (final step in [scheduleBackgroundAnalysis, services.bridge.markOpened, services.retryTextOnlyOnce]) {
    try {
      await step();
    } on Object catch (e) {
      debugPrint('Reel Analyser startup step failed: $e');
    }
  }
  unawaited(services.sweepPhotos().catchError((Object e) => debugPrint('sweepPhotos failed: $e')));
  if (await services.keys.flag('dark')) Brand.mode.value = ThemeMode.dark;
  Brand.mode.addListener(() => services.keys.setFlagTo('dark', Brand.mode.value == ThemeMode.dark));
  Brand.reduceEffects.value = await services.keys.flag('reduce_effects');
  Brand.reduceEffects.addListener(() => services.keys.setFlagTo('reduce_effects', Brand.reduceEffects.value));
  runApp(ReelBotApp(services, showIntro: !await services.keys.introSeen));
}

class ReelBotApp extends StatefulWidget {
  final AppServices services;
  final bool showIntro;
  const ReelBotApp(this.services, {required this.showIntro, super.key});

  @override
  State<ReelBotApp> createState() => _ReelBotAppState();
}

class _ReelBotAppState extends State<ReelBotApp> {
  late var _intro = widget.showIntro;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
      valueListenable: Brand.mode,
      builder: (_, mode, _) => MaterialApp(
        title: 'Reel Analyser',
        themeMode: mode,
        debugShowCheckedModeBanner: false,
        theme: Brand.theme(Brightness.light),
        darkTheme: Brand.theme(Brightness.dark),
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _intro
              ? IntroScreen(onDone: () async {
                  try {
                    await widget.services.keys.setIntroSeen();
                  } on Object catch (e) {
                    debugPrint('Could not remember the intro: $e');
                  }
                  if (mounted) setState(() => _intro = false);
                })
              : HomeScreen(widget.services),
        ),
      ));
}

class HomeScreen extends StatefulWidget {
  final AppServices services;
  const HomeScreen(this.services, {super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  var _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askConsent());
  }

  /// Once (and again if the documents change): the Terms and Privacy Policy, before anything else is used.
  Future<void> _askConsent() async {
    final k = widget.services.keys;
    if (await k.flag('legal_v1') || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Terms and Privacy'),
          content: const Text('Reel Analyser keeps your notes on this phone and sends a reel only to the AI service you choose, '
              'with your own key. Please read how your data is handled and the terms of use.'),
          actions: [
            TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => LegalScreen.privacy)), child: const Text('Privacy Policy')),
            TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => LegalScreen.terms)), child: const Text('Terms of Use')),
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Close app')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('I agree')),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await k.setFlag('legal_v1');
      } on Object catch (e) {
        debugPrint('Could not remember the agreement: $e');
      }
    } else {
      await SystemNavigator.pop();
    }
  }

  /// A banner when GitHub has a newer APK. Silent when offline or rate-limited.
  Future<void> _checkUpdate() async {
    final s = widget.services, now = DateTime.now().millisecondsSinceEpoch;
    if (now - await s.keys.updateCheckedAt < const Duration(days: 1).inMilliseconds) return;
    await s.keys.setUpdateCheckedAt(now);
    final rel = await newerRelease(s.client, AppServices.version);
    if (rel == null || !mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.showMaterialBanner(MaterialBanner(
      content: Text('Reel Analyser ${rel.$1} is out'),
      actions: [
        TextButton(onPressed: m.hideCurrentMaterialBanner, child: const Text('Later')),
        FilledButton(
          onPressed: () {
            m.hideCurrentMaterialBanner();
            s.bridge.openUrl(rel.$2);
          },
          child: const Text('Download'),
        ),
      ],
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.services.bridge.markOpened();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        // The liquid background is drawn once here, behind the tabs; the tab bar floats over it.
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(children: [
          const Positioned.fill(child: LiquidBackground()),
          FadingTabs(index: _tab, children: [
            ChatScreen(widget.services, onInsights: kPrivateBuild ? null : () => setState(() => _tab = 1)),
            if (!kPrivateBuild) InsightsScreen(widget.services),
            LibraryScreen(widget.services),
          ]),
        ]),
        bottomNavigationBar: GlassTabBar(
          index: _tab,
          onTap: (i) => setState(() => _tab = i),
          tabs: [
            const (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Ask'),
            if (!kPrivateBuild) const (Icons.insights_outlined, Icons.insights, 'Insights'),
            const (Icons.video_library_outlined, Icons.video_library, 'Library'),
          ],
        ),
      );
}
