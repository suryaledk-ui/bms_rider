import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../range.dart';
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
    final scheme = Theme.of(context).colorScheme;

    if (ride == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride')),
        body: const Center(child: Text('Ride ended')),
      );
    }

    final speed = app.currentSpeedKmh;
    final mode = modeForSpeed(speed);
    final distKm = ride.distanceM / 1000.0;
    final ec = distKm > 0.03 ? ride.whUsed / distKm : 0.0;
    final liveKm = t != null ? app.range.report(t, speed, 0).liveKm : double.nan;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopAndPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ride active'),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    speed.toStringAsFixed(1),
                    style: TextStyle(fontSize: 88, fontWeight: FontWeight.w800, color: scheme.onSurface),
                  ),
                  Text('km/h', style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  ModeChip(mode: modeName(mode), speed: speed <= 30 ? '10–30' : (speed <= 42 ? '30–42' : '42+')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SocRing(soc: t?.socPercent ?? 0, size: 120),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.7,
              children: [
                StatCard(label: 'Distance', value: distKm.toStringAsFixed(2), unit: 'km', icon: Icons.route),
                StatCard(label: 'Time', value: ride.durationLabel, unit: '', icon: Icons.timer),
                StatCard(
                  label: 'Energy',
                  value: ride.whUsed.toStringAsFixed(0),
                  unit: 'Wh',
                  icon: Icons.flash_on,
                ),
                StatCard(
                  label: 'Efficiency',
                  value: ec > 0 ? ec.toStringAsFixed(1) : '—',
                  unit: 'Wh/km',
                  icon: Icons.speed,
                ),
                StatCard(label: 'Voltage', value: t?.voltageV.toStringAsFixed(1) ?? '—', unit: 'V', icon: Icons.bolt),
                StatCard(
                  label: 'Power',
                  value: t?.powerW.abs().toStringAsFixed(0) ?? '—',
                  unit: 'W',
                  icon: Icons.electric_bolt,
                ),
              ],
            ),
            if (t != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Live range estimate',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                        const SizedBox(height: 8),
                        Text(
                          liveKm.isFinite ? '${liveKm.toStringAsFixed(0)} km remaining' : '—',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.primary),
                        ),
                        Text(
                          'based on current ${modeName(mode)} consumption',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Rider learn mode: ${app.range.factors.factorFor(mode).toStringAsFixed(2)}× '
                      'vs physics baseline — updates after each ride.',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ],
            FilledButton.icon(
              onPressed: _stopAndPop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop ride'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: const Color(0xFFFF5252),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
