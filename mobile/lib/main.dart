import 'package:flutter/material.dart';

import 'app_services.dart';
import 'pipeline/background.dart';
import 'ui/library_screen.dart';

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
        home: LibraryScreen(services),
      );
}
