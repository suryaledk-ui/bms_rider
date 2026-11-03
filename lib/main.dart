import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'src/controller.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: VoltTokens.bgCanvas,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
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
      theme: buildVoltTheme(),
      home: const AppShell(),
    );
  }
}
