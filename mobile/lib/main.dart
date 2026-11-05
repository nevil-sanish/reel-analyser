import 'package:flutter/material.dart';

import 'app_services.dart';
import 'pipeline/background.dart';
import 'ui/chat_screen.dart';
import 'ui/intro_screen.dart';
import 'ui/library_screen.dart';
import 'ui/liquid.dart';
import 'ui/theme.dart';
import 'ui/insights_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  await scheduleBackgroundAnalysis();
  await services.bridge.markOpened();
  await services.retryTextOnlyOnce();
  if (await services.keys.flag('dark')) Brand.mode.value = ThemeMode.dark;
  Brand.mode.addListener(() => services.keys.setFlagTo('dark', Brand.mode.value == ThemeMode.dark));
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
        title: 'Reel Bot',
        themeMode: mode,
        debugShowCheckedModeBanner: false,
        theme: Brand.theme(Brightness.light),
        darkTheme: Brand.theme(Brightness.dark),
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _intro
              ? IntroScreen(onDone: () {
                  widget.services.keys.setIntroSeen();
                  setState(() => _intro = false);
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
        // The liquid background is drawn once here, behind all three tabs; the tab bar floats over it.
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(children: [
          const Positioned.fill(child: LiquidBackground()),
          // All three stay alive (like IndexedStack) but cross-fade and settle, so switching tabs feels liquid.
          for (final (i, page) in [ChatScreen(widget.services, onInsights: () => setState(() => _tab = 1)), InsightsScreen(widget.services), LibraryScreen(widget.services)].indexed)
            IgnorePointer(
              ignoring: i != _tab,
              child: TickerMode(
                enabled: i == _tab,
                child: AnimatedOpacity(
                  opacity: i == _tab ? 1 : 0,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: AnimatedScale(
                    scale: i == _tab ? 1 : 0.97,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutQuint,
                    child: page,
                  ),
                ),
              ),
            ),
        ]),
        bottomNavigationBar: GlassTabBar(
          index: _tab,
          onTap: (i) => setState(() => _tab = i),
          tabs: const [
            (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Ask'),
            (Icons.insights_outlined, Icons.insights, 'Insights'),
            (Icons.video_library_outlined, Icons.video_library, 'Library'),
          ],
        ),
      );
}
