import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/controller.dart';
import 'src/ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await controller.init();
  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const BmsRiderApp(),
    ),
  );
}

class BmsRiderApp extends StatelessWidget {
  const BmsRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BMS Rider',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5A0),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
        cardTheme: const CardThemeData(
          color: Color(0xFF141A22),
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        ),
      ),
      home: const AppShell(),
    );
  }
}
