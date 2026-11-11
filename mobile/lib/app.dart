import 'dart:async';

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_services.dart';
import 'features.dart';
import 'core/distribution.dart';
import 'data/update_check.dart';
import 'pipeline/background.dart';
import 'ui/chat_screen.dart';
import 'ui/intro_screen.dart';
import 'ui/legal_screen.dart';
import 'ui/library_screen.dart';
import 'ui/liquid.dart';
import 'ui/motion.dart';
import 'ui/theme.dart';
import 'ui/about_screen.dart';

/// Starts the app with what this build adds. `main_full.dart` and `main_semi.dart` call this: nothing else imports a build's own code.
Future<void> runReelBot(AppFeatures features, void Function() backgroundDispatcher) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled fonts are under the SIL Open Font Licence: list them with the other open-source licences.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Cormorant Garamond (font)'], await rootBundle.loadString('assets/fonts/OFL-CormorantGaramond.txt'));
    yield LicenseEntryWithLineBreaks(['Lato (font)'], await rootBundle.loadString('assets/fonts/OFL-Lato.txt'));
  });
  final services = await AppServices.create(features);
  // None of these is worth a blank screen at launch if the phone refuses one: the app opens without it.
  for (final step in [() => scheduleBackgroundAnalysis(backgroundDispatcher), services.retryTextOnlyOnce]) {
    try {
      await step();
    } on Object catch (e) {
      debugPrint('Reel Analyser startup step failed: $e');
    }
  }
  unawaited(services.sweepPhotos().catchError((Object e) => debugPrint('sweepPhotos failed: $e')));
  if (await services.keys.flag('dark')) Brand.mode.value = ThemeMode.dark;
  Brand.mode.addListener(() => services.keys.setFlagTo('dark', Brand.mode.value == ThemeMode.dark));
  Haptics.enabled = !await services.keys.flag('haptics_off');
  Brand.reduceEffects.value = await services.keys.flag('reduce_effects');
  Brand.reduceEffects.addListener(() => services.keys.setFlagTo('reduce_effects', Brand.reduceEffects.value));
  // Draw behind the status and navigation bars: the marble runs to the edges of the screen.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
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
    widget.services.features.onOpen(widget.services);
    WidgetsBinding.instance.addPostFrameCallback((_) => _askConsent());
  }

  /// Once (and again if the documents change): the Terms and Privacy Policy, before anything else is used.
  Future<void> _askConsent() async {
    final k = widget.services.keys;
    if (await k.flag('legal_v5') || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Terms, Privacy and Disclaimer'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Reel Analyser keeps your notes on this phone and sends a reel only to the AI service you choose, '
                'with your own key. The legal texts were updated: LinkedIn and folders are described, there is a new Support and Refund Policy for the optional support payments, and a contact email. Please read them.'),
            const SizedBox(height: 8),
            Wrap(spacing: 4, children: [
              for (final (label, page) in [('Privacy Policy', LegalScreen.privacy), ('Terms of Use', LegalScreen.terms), ('Disclaimer', LegalScreen.disclaimer), ('Support and refunds', LegalScreen.support)])
                ActionChip(label: Text(label), onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => page))),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Close app')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('I agree')),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await k.setFlag('legal_v5');
      } on Object catch (e) {
        debugPrint('Could not remember the agreement: $e');
      }
    } else {
      await SystemNavigator.pop();
    }
  }

  /// A banner when GitHub has a newer APK. Silent when offline or rate-limited.
  Future<void> _checkUpdate() async {
    if (fromFdroid) return;
    final s = widget.services, now = DateTime.now().millisecondsSinceEpoch;
    if (now - await s.keys.updateCheckedAt < const Duration(days: 1).inMilliseconds) return;
    await s.keys.setUpdateCheckedAt(now);
    final rel = await latestUpdate(s.client, AppServices.version, semi: s.features.flavor == 'semi');
    if (rel == null || !mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.showMaterialBanner(MaterialBanner(
      content: Text('Reel Analyser ${rel.tag} is out'),
      actions: [
        TextButton(onPressed: m.hideCurrentMaterialBanner, child: const Text('Later')),
        FilledButton(
          onPressed: () {
            m.hideCurrentMaterialBanner();
            s.features.installUpdate(context, s, rel);
          },
          child: Text(s.features.flavor == 'semi' ? 'Download' : 'Update'),
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
    if (state == AppLifecycleState.resumed) widget.services.features.onOpen(widget.services);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.services.features;
    final s = widget.services;
    // Ask, then what this build adds after it (Insights), Library, what it adds before About (the blocker), About.
    final extra = [...f.afterAsk];
    final late = [...f.beforeAbout];
    final tabs = <(IconData, IconData, String)>[
      (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Ask'),
      for (final t in extra) (t.icon, t.activeIcon, t.label),
      (Icons.video_library_outlined, Icons.video_library, 'Library'),
      for (final t in late) (t.icon, t.activeIcon, t.label),
      (Icons.info_outline_rounded, Icons.info_rounded, 'About'),
    ];
    final pages = <Widget>[
      ChatScreen(s, onInsights: extra.isEmpty ? null : () => setState(() => _tab = 1)),
      for (var i = 0; i < extra.length; i++) extra[i].build(s, _tab == 1 + i),
      LibraryScreen(s),
      for (var i = 0; i < late.length; i++) late[i].build(s, _tab == 2 + extra.length + i),
      AboutScreen(s),
    ];
    return Scaffold(
      // The marble background is drawn once here, behind the tabs; the tab bar floats over it.
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(children: [
        const Positioned.fill(child: LiquidBackground()),
        FadingTabs(index: _tab, children: pages),
      ]),
      bottomNavigationBar: GlassTabBar(index: _tab, onTap: (i) => setState(() => _tab = i), tabs: tabs),
    );
  }
}
