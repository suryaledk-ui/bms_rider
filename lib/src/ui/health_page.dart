import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  final _whController = TextEditingController();
  String? _calibMsg;

  @override
  void dispose() {
    _whController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final t = app.bms.latest;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Battery health')),
      body: t == null
          ? const Center(child: Text('Connect a scooter to see battery health.'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const SizedBox(height: 8),
                _SohCard(app: app, t: t),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cell voltages',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                        const SizedBox(height: 12),
                        if (t.cellVolts.isEmpty)
                          Text('Cell data not available from this BMS yet.',
                              style: TextStyle(color: scheme.onSurfaceVariant))
                        else
                          SizedBox(
                            height: 160,
                            child: BarChart(
                              BarChartData(
                                maxY: (t.cellMaxV + 0.2).clamp(4.0, 5.0),
                                minY: (t.cellMinV - 0.2).clamp(0.0, 4.0),
                                gridData: FlGridData(show: true, drawVerticalLine: false),
                                borderData: FlBorderData(show: false),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 36,
                                      getTitlesWidget: (v, _) => Text(
                                        v.toStringAsFixed(1),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ),
                                  bottomTitles: const AxisTitles(),
                                  rightTitles: const AxisTitles(),
                                  topTitles: const AxisTitles(),
                                ),
                                barGroups: [
                                  for (var i = 0; i < t.cellVolts.length; i++)
                                    BarChartGroupData(
                                      x: i,
                                      barRods: [
                                        BarChartRodData(
                                          toY: t.cellVolts[i],
                                          color: t.cellVolts[i] < t.cellMinV + 0.05
                                              ? const Color(0xFFFFB300)
                                              : scheme.primary,
                                          width: 6,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Calibrate',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                        const SizedBox(height: 4),
                        Text(
                          'After a full discharge + full charge, enter energy the charger drew from the wall (Wh) to measure true capacity.',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _whController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Wall energy (Wh)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () {
                                final v = double.tryParse(_whController.text);
                                if (v == null || v <= 0) {
                                  setState(() => _calibMsg = 'Enter a valid Wh value.');
                                  return;
                                }
                                final nomWh = t.nominalAh > 0 ? t.nominalAh * t.voltageV : 960.0;
                                final soh = (v * 0.88 / nomWh * 100).clamp(20.0, 110.0);
                                app.store.setUsableWh(v * 0.88); // ~88% charger efficiency
                                app.store.setCalibratedSoH(soh);
                                setState(() =>
                                    _calibMsg = 'Calibrated: SOH ≈ ${soh.toStringAsFixed(0)}% · usable ${(v * 0.88).toStringAsFixed(0)} Wh');
                              },
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                        if (_calibMsg != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_calibMsg!, style: TextStyle(fontSize: 12, color: scheme.primary)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SohCard extends StatelessWidget {
  final AppController app;
  final dynamic t;

  const _SohCard({required this.app, required this.t});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final health = app.range.health(t, calibratedSoH: app.store.calibratedSoH);
    final color = health.sohPercent >= 90
        ? const Color(0xFF00E5A0)
        : health.sohPercent >= 75
            ? const Color(0xFFFFB300)
            : const Color(0xFFFF5252);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 110,
                        height: 110,
                        child: CircularProgressIndicator(
                          value: health.sohPercent / 100,
                          strokeWidth: 10,
                          backgroundColor: const Color(0xFF1C2530),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${health.sohPercent.toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: scheme.onSurface),
                          ),
                          Text('SOH', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(health.note,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      _kv('Cycles', '${health.cycles}'),
                      _kv('Cell spread', '${health.cellSpreadMv.toStringAsFixed(0)} mV'),
                      _kv('Thermal sag', '${health.sagDropV.toStringAsFixed(1)} V @ load'),
                      _kv('Protocol', t.protocol),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(k, style: const TextStyle(fontSize: 12))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
