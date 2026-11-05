import 'package:flutter/material.dart';

import 'app_services.dart';
import 'pipeline/background.dart';
import 'ui/library_screen.dart';
import 'ui/today_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  await scheduleBackgroundAnalysis();
  runApp(ReelBotApp(services));
}

class ReelBotApp extends StatelessWidget {
  final AppServices services;
  const ReelBotApp(this.services, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Reel Bot',
        theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: Colors.deepPurple, brightness: Brightness.dark, useMaterial3: true),
        home: HomeScreen(services),
      );
}

class HomeScreen extends StatefulWidget {
  final AppServices services;
  const HomeScreen(this.services, {super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: [TodayScreen(widget.services), LibraryScreen(widget.services)]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.video_library_outlined), label: 'Library'),
          ],
        ),
      );
}
