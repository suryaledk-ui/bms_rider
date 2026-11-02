import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bms_manager.dart';
import '../controller.dart';
import '../range.dart';
import 'log_page.dart';
import 'ride_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _scanning = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final bms = app.bms;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BMS Rider'),
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal),
            tooltip: 'Scan logs',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => app.requestPermissionsAndScan(),
            tooltip: 'Rescan',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => app.requestPermissionsAndScan(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ConnectionBanner(
              state: bms.state,
              status: bms.status,
              protocol: bms.proto?.name,
              onTap: () => _showScanSheet(context, app),
            ),
            if (bms.state == BmsState.scanning)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    const ScanRadar(),
                    const SizedBox(height: 16),
                    Text(
                      'Listening for your scooter…',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Keep the scooter ON and nearby',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (bms.state != BmsState.scanning && bms.candidates.isNotEmpty) ..._candidateList(app),
            if (bms.latest != null) ..._liveSection(context, app),
            if (app.ride == null && bms.latest != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RidePage()),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start ride'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            if (bms.latest == null && bms.state == BmsState.idle)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Scan for your scooter BMS to begin.\n'
                    'Turn the scooter ON first. Location is only needed for ride tracking.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _candidateList(AppController app) {
    final bms = app.bms;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          'Found ${bms.candidates.length} BMS device(s)',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      ...bms.candidates.map((c) {
        return Card(
          child: ListTile(
            leading: const Icon(Icons.battery_charging_full),
            title: Text(c.name),
            subtitle: Text('${c.guess} · ${c.id}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${c.rssi} dBm',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    await bms.connectTo(c);
                  },
                  child: const Text('Pair'),
                ),
              ],
            ),
          ),
        );
      }),
    ];
  }

  List<Widget> _liveSection(BuildContext context, AppController app) {
    final t = app.bms.latest!;
    final scheme = Theme.of(context).colorScheme;
    final speed = app.currentSpeedKmh;
    final mode = modeForSpeed(speed);
    final report = app.range.report(t, speed, 0);

    return [
      const SizedBox(height: 8),
      Center(
        child: ModeChip(
          mode: modeName(mode),
          speed: '${speed.toStringAsFixed(0)} km/h',
        ),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SocRing(soc: t.socPercent),
        ],
      ),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.7,
        children: [
          StatCard(label: 'Voltage', value: t.voltageV.toStringAsFixed(1), unit: 'V', icon: Icons.bolt),
          StatCard(
            label: 'Current',
            value: t.currentA.toStringAsFixed(1),
            unit: 'A',
            icon: Icons.electric_bolt,
            color: t.currentA > 0 ? const Color(0xFFFFB300) : const Color(0xFF00E5A0),
          ),
          StatCard(
            label: 'Power',
            value: t.powerW.abs().toStringAsFixed(0),
            unit: 'W',
            icon: Icons.flash_on,
          ),
          StatCard(
            label: 'Cells',
            value: t.cellVolts.isEmpty ? '—' : '${t.cellMinV.toStringAsFixed(2)}–${t.cellMaxV.toStringAsFixed(2)}',
            unit: 'V',
            icon: Icons.grid_view,
          ),
        ],
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.route, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Estimated range', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              _rangeTile('Eco', '10–30 km/h', report.ecoKm, isActive: mode == RideMode.eco),
              const SizedBox(height: 8),
              _rangeTile('Sports', '30–42 km/h', report.sportsKm, isActive: mode == RideMode.sports),
              const SizedBox(height: 8),
              _rangeTile('Hyper', '42+ km/h', report.hyperKm, isActive: mode == RideMode.hyper),
              const Divider(height: 24),
              _rangeTile('Now', 'current speed', report.liveKm, isActive: false, emphasize: true),
            ],
          ),
        ),
      ),
      if (app.lastDiagnostic != null) _diagnosticCard(context, app.lastDiagnostic!),
    ];
  }

  Widget _rangeTile(String label, String sub, double km, {required bool isActive, bool emphasize = false}) {
    final scheme = Theme.of(context).colorScheme;
    final color = emphasize ? scheme.primary : (isActive ? scheme.primary : scheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive || emphasize ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                const SizedBox(width: 8),
                Text(sub, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            km.isFinite ? '${km.toStringAsFixed(0)} km' : '—',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color),
          ),
        ],
      ),
    );
  }

  Widget _diagnosticCard(BuildContext context, DiagnosticResult d) {
    final scheme = Theme.of(context).colorScheme;
    final color = d.lessRange ? const Color(0xFFFFB300) : const Color(0xFF00E5A0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(d.lessRange ? Icons.warning_amber : Icons.check_circle, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
            if (d.hints.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...d.hints.map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(h, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showScanSheet(BuildContext context, AppController app) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connect scooter',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Theme.of(ctx).colorScheme.onSurface)),
                    const SizedBox(height: 8),
                    Text(
                      'Turn the scooter ON, keep it near the phone, then scan. '
                      'Location permission is NOT needed for connecting — only for ride tracking.',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        setSheetState(() => _scanning = true);
                        await app.requestPermissionsAndScan();
                        setSheetState(() => _scanning = false);
                      },
                      icon: Icon(_scanning ? Icons.bluetooth_searching : Icons.bluetooth_searching),
                      label: Text(_scanning ? 'Scanning…' : 'Scan for BMS'),
                    ),
                    const SizedBox(height: 12),
                    if (_scanning)
                      Center(
                        child: Column(
                          children: const [
                            ScanRadar(size: 110),
                            SizedBox(height: 12),
                            Text('Looking for your scooter…'),
                          ],
                        ),
                      )
                    else if (app.bms.candidates.isEmpty)
                      Text(
                        'No BMS found yet.',
                        style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                      )
                    else
                      SizedBox(
                        height: 240,
                        child: ListView.builder(
                          itemCount: app.bms.candidates.length,
                          itemBuilder: (_, i) {
                            final c = app.bms.candidates[i];
                            return ListTile(
                              leading: const Icon(Icons.battery_charging_full),
                              title: Text(c.name),
                              subtitle: Text('${c.guess} · ${c.id} · ${c.rssi} dBm'),
                              trailing: FilledButton.tonal(
                                onPressed: () async {
                                  await app.bms.connectTo(c);
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                },
                                child: const Text('Pair'),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
