import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../range.dart';
import 'theme.dart';
import 'widgets.dart';

class RidePage extends StatefulWidget {
  const RidePage({super.key});

  @override
  State<RidePage> createState() => _RidePageState();
}

class _RidePageState extends State<RidePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppController>().startRide();
    });
  }

  Future<void> _stopAndPop() async {
    final navigator = Navigator.of(context);
    await context.read<AppController>().stopRide();
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final ride = app.ride;
    final t = app.bms.latest;

    if (ride == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: VoltEmptyState(
              icon: Icons.stop_circle_outlined,
              eyebrow: 'Session ended',
              title: 'Ride ended',
              message: 'Your trip was saved to Trips.',
              accent: VoltTokens.voltMint,
            ),
          ),
        ),
      );
    }

    final speed = app.currentSpeedKmh;
    final mode = modeForSpeed(speed);
    final distKm = ride.distanceM / 1000.0;
    final ec = distKm > 0.03 ? ride.whUsed / distKm : 0.0;
    final liveKm =
        t != null ? app.range.report(t, speed, 0).liveKm : double.nan;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopAndPop();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PulseDot(),
              const SizedBox(width: 10),
              const Text('Ride active'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _stopAndPop,
              style: TextButton.styleFrom(
                foregroundColor: VoltTokens.voltCoral,
              ),
              child: const Text('END'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _SpeedHero(speed: speed),
            const SizedBox(height: 24),
            Center(
              child: SocRing(
                soc: t?.socPercent ?? 0,
                size: 132,
                label: 'SOC',
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.6,
              children: [
                StatCard(
                  label: 'Distance',
                  value: distKm.toStringAsFixed(2),
                  unit: 'km',
                  icon: Icons.route_rounded,
                  color: VoltTokens.voltCyan,
                ),
                StatCard(
                  label: 'Time',
                  value: ride.durationLabel,
                  unit: '',
                  icon: Icons.timer_outlined,
                ),
                StatCard(
                  label: 'Energy',
                  value: ride.whUsed.toStringAsFixed(0),
                  unit: 'Wh',
                  icon: Icons.flash_on_rounded,
                  color: VoltTokens.voltAmber,
                ),
                StatCard(
                  label: 'Efficiency',
                  value: ec > 0 ? ec.toStringAsFixed(1) : '—',
                  unit: 'Wh/km',
                  icon: Icons.speed_rounded,
                  color: VoltTokens.voltMint,
                ),
                StatCard(
                  label: 'Voltage',
                  value: t?.voltageV.toStringAsFixed(1) ?? '—',
                  unit: 'V',
                  icon: Icons.bolt_rounded,
                  color: VoltTokens.voltCyan,
                ),
                StatCard(
                  label: 'Power',
                  value: t?.powerW.abs().toStringAsFixed(0) ?? '—',
                  unit: 'W',
                  icon: Icons.electric_bolt_rounded,
                  color: (t?.powerW ?? 0) > 0
                      ? VoltTokens.voltAmber
                      : VoltTokens.voltMint,
                ),
              ],
            ),
            if (t != null) ...[
              const SizedBox(height: 14),
              VoltCard(
                accentColor: VoltTokens.voltMint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LIVE RANGE ESTIMATE',
                      style: VoltType.labelMicro.copyWith(
                        color: VoltTokens.voltMint,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      liveKm.isFinite ? '${liveKm.toStringAsFixed(0)} km' : '—',
                      style: VoltType.displayLarge.copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'based on current ${modeName(mode)} consumption',
                      style: VoltType.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              VoltCard(
                child: Row(
                  children: [
                    const Icon(
                      Icons.insights_rounded,
                      size: 20,
                      color: VoltTokens.voltCyan,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Rider learn mode: ${app.range.factors.factorFor(mode).toStringAsFixed(2)}× '
                        'vs physics baseline — updates after each ride.',
                        style: VoltType.body.copyWith(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _stopAndPop,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop ride'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: VoltTokens.voltCoral,
                foregroundColor: const Color(0xFFFFF1F2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: VoltTokens.voltCoral,
            boxShadow: [
              BoxShadow(
                color: VoltTokens.voltCoral.withValues(
                  alpha: 0.25 + 0.45 * _controller.value,
                ),
                blurRadius: 4 + 8 * _controller.value,
                spreadRadius: 1 + 2 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SpeedHero extends StatelessWidget {
  final double speed;
  const _SpeedHero({required this.speed});

  @override
  Widget build(BuildContext context) {
    final capped = speed.clamp(0.0, 90.0);
    final fraction = capped / 90.0;

    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          'CURRENT SPEED',
          style: VoltType.labelMicro.copyWith(
            letterSpacing: 2.0,
            color: VoltTokens.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: speed),
          duration: VoltTokens.medium,
          curve: VoltTokens.curveOut,
          builder: (context, value, _) {
            return Text(
              value.toStringAsFixed(0),
              style: VoltType.displayHero.copyWith(
                fontSize: 96,
                shadows: [
                  Shadow(
                    color: VoltTokens.voltMint.withValues(alpha: 0.18),
                    blurRadius: 28,
                  ),
                ],
              ),
            );
          },
        ),
        Text(
          'km/h',
          style: VoltType.sectionTitle.copyWith(
            color: VoltTokens.textSecondary,
            letterSpacing: 3,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _EnergyRibbon(fraction: fraction),
        ),
        const SizedBox(height: 10),
        Text(
          '${(fraction * 90).round()} / 90 km/h',
          style: VoltType.labelMicro.copyWith(fontSize: 10.5),
        ),
      ],
    );
  }
}

class _EnergyRibbon extends StatelessWidget {
  final double fraction;
  const _EnergyRibbon({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 18,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                width: width,
                height: 6,
                decoration: BoxDecoration(
                  color: VoltTokens.bgInteractive,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: VoltTokens.borderSubtle),
                ),
              ),
              AnimatedContainer(
                duration: VoltTokens.fast,
                curve: VoltTokens.curveOut,
                width: width * f,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    colors: [
                      VoltTokens.voltMint,
                      VoltTokens.voltCyan,
                    ],
                  ),
                ),
              ),
              AnimatedAlign(
                duration: VoltTokens.fast,
                curve: VoltTokens.curveOut,
                alignment: Alignment(-1 + 2 * f, 0),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: VoltTokens.textPrimary,
                    border: Border.all(
                      color: VoltTokens.voltMintBright,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: VoltTokens.voltMint.withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
