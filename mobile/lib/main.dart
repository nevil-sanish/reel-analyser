import 'package:flutter/material.dart';

import 'app_services.dart';
import 'pipeline/background.dart';
import 'ui/chat_screen.dart';
import 'ui/intro_screen.dart';
import 'ui/library_screen.dart';
import 'ui/liquid.dart';
import 'ui/theme.dart';
import 'ui/today_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  await scheduleBackgroundAnalysis();
  await services.bridge.markOpened();
  await services.retryTextOnlyOnce();
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
  Widget build(BuildContext context) => MaterialApp(
        title: 'Reel Bot',
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
      );
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
          IndexedStack(index: _tab, children: [ChatScreen(widget.services), TodayScreen(widget.services), LibraryScreen(widget.services)]),
        ]),
        bottomNavigationBar: GlassTabBar(
          index: _tab,
          onTap: (i) => setState(() => _tab = i),
          tabs: const [
            (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Ask'),
            (Icons.insights_outlined, Icons.insights, 'Today'),
            (Icons.video_library_outlined, Icons.video_library, 'Library'),
          ],
        ),
      );
}
