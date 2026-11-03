import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bms_manager.dart';
import '../controller.dart';
import 'health_page.dart';
import 'history_page.dart';
import 'home_page.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const List<Widget> _pages = [
    HomePage(),
    HistoryPage(),
    HealthPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final isConnected = app.bms.state == BmsState.connected;
    final soc = app.bms.latest?.socPercent;

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: VoltTokens.bgSurface,
          border: Border(
            top: BorderSide(color: VoltTokens.borderSubtle, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _NavPill(
                    selected: _index == 0,
                    icon: Icons.bolt_rounded,
                    label: 'Cockpit',
                    badgeText: isConnected && soc != null ? '$soc%' : null,
                    badgeColor: soc != null ? VoltTokens.socColor(soc) : VoltTokens.voltMint,
                    onTap: () => setState(() => _index = 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NavPill(
                    selected: _index == 1,
                    icon: Icons.route_rounded,
                    label: 'Trips',
                    badgeText: app.history.isNotEmpty ? '${app.history.length}' : null,
                    badgeColor: VoltTokens.voltCyan,
                    onTap: () => setState(() => _index = 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NavPill(
                    selected: _index == 2,
                    icon: Icons.battery_charging_full_rounded,
                    label: 'Cells & SOH',
                    onTap: () => setState(() => _index = 2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final String? badgeText;
  final Color badgeColor;
  final VoidCallback onTap;

  const _NavPill({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeText,
    this.badgeColor = VoltTokens.voltMint,
  });

  @override
  Widget build(BuildContext context) {
    final accent = VoltTokens.voltMint;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VoltTokens.r16),
        child: AnimatedContainer(
          duration: VoltTokens.fast,
          curve: VoltTokens.curveOut,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(VoltTokens.r16),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.38)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? accent : VoltTokens.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VoltType.caption.copyWith(
                    color: selected ? VoltTokens.textPrimary : VoltTokens.textSecondary,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (badgeText != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(VoltTokens.rPill),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    badgeText!,
                    style: VoltType.labelMicro.copyWith(
                      fontSize: 9.5,
                      color: badgeColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
