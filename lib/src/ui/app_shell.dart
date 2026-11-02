import 'package:flutter/material.dart';

import 'health_page.dart';
import 'history_page.dart';
import 'home_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomePage(),
      const HistoryPage(),
      const HealthPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'Ride'),
          NavigationDestination(icon: Icon(Icons.route), label: 'Trips'),
          NavigationDestination(icon: Icon(Icons.battery_charging_full), label: 'Battery'),
        ],
      ),
    );
  }
}
