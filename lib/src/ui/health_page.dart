import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  final _whController = TextEditingController();
  String? _calibMsg;
  bool _calibOk = false;

  @override
  void dispose() {
    _whController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final t = app.bms.latest;

    return Scaffold(
      appBar: AppBar(title: const Text('Battery health')),
      body: t == null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: VoltEmptyState(
                  icon: Icons.battery_unknown_rounded,
                  eyebrow: 'No telemetry',
                  title: 'Connect a scooter',
                  message: 'Battery health, cell balance and SOH appear here '
                      'once your BMS is linked.',
                  accent: VoltTokens.voltMint,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                const SizedBox(height: 8),
                _SohCard(app: app, t: t),
                if (app.estimatedCapacityWh != null) ...[
                  const SizedBox(height: 10),
                  _AutoCapacityCard(app: app),
                ],
                const SizedBox(height: 10),
                const VoltSectionHeader(
                  eyebrow: 'Cell balance',
                  title: 'Cell voltages',
                  icon: Icons.grid_view_rounded,
                ),
                _CellChartCard(t: t),
                const SizedBox(height: 10),
                const VoltSectionHeader(
                  eyebrow: 'Calibration',
                  title: 'Measure true capacity',
                  icon: Icons.handyman_outlined,
                ),
                _CalibrateCard(
                  t: t,
                  controller: _whController,
                  message: _calibMsg,
                  isOk: _calibOk,
                  onSubmit: _calibrate,
                ),
              ],
            ),
    );
  }

  void _calibrate(Telemetry t) {
    final v = double.tryParse(_whController.text);
    if (v == null || v <= 0) {
      setState(() {
        _calibMsg = 'Enter a valid Wh value.';
        _calibOk = false;
      });
      return;
    }
    final nomWh = t.nominalAh > 0 ? t.nominalAh * t.voltageV : 960.0;
    final soh = (v * 0.88 / nomWh * 100).clamp(20.0, 110.0);
    final app = context.read<AppController>();
    app.store.setUsableWh(v * 0.88); // ~88% charger efficiency
    app.store.setCalibratedSoH(soh);
    setState(() {
      _calibMsg =
          'Calibrated: SOH ≈ ${soh.toStringAsFixed(0)}% · usable ${(v * 0.88).toStringAsFixed(0)} Wh';
      _calibOk = true;
    });
  }
}

class _SohCard extends StatelessWidget {
  final AppController app;
  final Telemetry t;

  const _SohCard({required this.app, required this.t});

  @override
  Widget build(BuildContext context) {
    final health = app.range.health(t, calibratedSoH: app.store.calibratedSoH);
    final color = VoltTokens.socColor(health.sohPercent);

    return VoltCard(
      accentColor: color,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        children: [
          Row(
            children: [
              SocRing(
                soc: health.sohPercent.round(),
                size: 128,
                label: 'SOH',
                sublabel: '${health.cycles} cycles',
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      health.note,
                      style: VoltType.bodyStrong.copyWith(fontSize: 13.5),
                    ),
                    const SizedBox(height: 12),
                    _kvRow(
                      context,
                      Icons.cyclone_rounded,
                      'Cycles',
                      '${health.cycles}',
                      VoltTokens.voltCyan,
                      help: 'A cycle = one full charge + discharge of the pack. '
                          '473 is typical for a used scooter pack. Li-ion packs '
                          'hold ~80% capacity at 900–1400 cycles.',
                    ),
                    const SizedBox(height: 8),
                    _kvRow(
                      context,
                      Icons.tune_rounded,
                      'Cell spread',
                      '${health.cellSpreadMv.toStringAsFixed(0)} mV',
                      VoltTokens.voltAmber,
                      help: 'Difference between the highest and lowest cell '
                          'voltage. Under ~30 mV is healthy; larger gaps mean '
                          'the pack needs balancing.',
                    ),
                    const SizedBox(height: 8),
                    _kvRow(
                      context,
                      Icons.thermostat_rounded,
                      'Thermal sag',
                      '${health.sagDropV.toStringAsFixed(1)} V @ load',
                      VoltTokens.voltCoral,
                      help: 'How much pack voltage sags under load. Higher sag '
                          '= higher internal resistance, weak or hot cells.',
                    ),
                    const SizedBox(height: 8),
                    _kvRow(
                      context,
                      Icons.device_thermostat_rounded,
                      'Pack temp',
                      _tempLabel(),
                      VoltTokens.voltMint,
                      help: 'Temperatures reported by sensors inside the pack '
                          '(°C). Keep under ~50°C when riding or charging.',
                    ),
                    const SizedBox(height: 8),
                    _kvRow(
                      context,
                      Icons.memory_rounded,
                      'Protocol',
                      t.protocol,
                      VoltTokens.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kvRow(BuildContext context, IconData icon, String label, String value,
      Color color, {String? help}) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 13, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: VoltType.caption.copyWith(fontSize: 11.5),
                ),
              ),
              if (help != null) ...[
                const SizedBox(width: 3),
                GestureDetector(
                  onTap: () => _showHelp(context, label, help),
                  child: Icon(
                    Icons.help_outline_rounded,
                    size: 13,
                    color: VoltTokens.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: VoltType.caption.copyWith(
              color: VoltTokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  void _showHelp(BuildContext context, String title, String text) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VoltTokens.bgElevated,
        title: Text(title, style: VoltType.bodyStrong),
        content: Text(text, style: VoltType.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  String _tempLabel() {
    final temps = t.tempsC;
    if (temps.isEmpty) return '—';
    final c = temps.map((x) => x.toStringAsFixed(1)).join(' / ');
    var extra = '';
    final mx = temps.reduce((a, b) => a > b ? a : b);
    if (mx > 50) extra = ' · HOT';
    if (mx < 0) extra = ' · cold';
    return '$c°C$extra';
  }
}

class _CellChartCard extends StatelessWidget {
  final Telemetry t;
  const _CellChartCard({required this.t});

  @override
  Widget build(BuildContext context) {
    if (t.cellVolts.isEmpty) {
      return const VoltCard(
        child: Text(
          'Cell data not available from this BMS yet.',
          style: VoltType.body,
        ),
      );
    }

    final minV = t.cellMinV;
    final minIdx = t.cellVolts.indexOf(minV) + 1;
    final spread = t.cellSpreadMv;

    return VoltCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: VoltTokens.voltAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: VoltTokens.voltAmber.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Δ $spread mV · lowest cell #$minIdx (${minV.toStringAsFixed(2)} V)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VoltType.caption.copyWith(
                      fontSize: 11.5,
                      color: VoltTokens.voltAmber,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${t.cellVolts.length} cells',
                style: VoltType.labelMicro,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: BarChart(
              BarChartData(
                maxY: (t.cellMaxV + 0.2).clamp(4.0, 5.0),
                minY: (minV - 0.2).clamp(0.0, 4.0),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 0.1,
                  getDrawingHorizontalLine: (value) => const FlLine(
                    color: VoltTokens.borderSubtle,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(1),
                        style: VoltType.labelMicro.copyWith(fontSize: 9.5),
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
                          width: 6,
                          color: t.cellVolts[i] <= minV + 0.005
                              ? VoltTokens.voltAmber
                              : VoltTokens.voltMint,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ],
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

class _CalibrateCard extends StatelessWidget {
  final Telemetry t;
  final TextEditingController controller;
  final String? message;
  final bool isOk;
  final void Function(Telemetry t) onSubmit;

  const _CalibrateCard({
    required this.t,
    required this.controller,
    required this.message,
    required this.isOk,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return VoltCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'After a full discharge + full charge, enter the energy the '
            'charger drew from the wall (Wh) to measure true capacity.',
            style: VoltType.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Wall energy (Wh)',
                    prefixIcon: Icon(
                      Icons.electric_bolt_rounded,
                      size: 18,
                      color: VoltTokens.voltMint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: () => onSubmit(t),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  backgroundColor: VoltTokens.voltMint.withValues(alpha: 0.12),
                  foregroundColor: VoltTokens.voltMint,
                ),
                child: const Text('Save'),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isOk ? VoltTokens.voltMint : VoltTokens.voltCoral)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (isOk ? VoltTokens.voltMint : VoltTokens.voltCoral)
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isOk
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 16,
                    color: isOk ? VoltTokens.voltMint : VoltTokens.voltCoral,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message!,
                      style: VoltType.caption.copyWith(
                        color: isOk
                            ? VoltTokens.textPrimary
                            : VoltTokens.voltCoral,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows the auto-estimated usable capacity (coulomb counting) when the app
/// has gathered enough real discharge data.
class _AutoCapacityCard extends StatelessWidget {
  final AppController app;
  const _AutoCapacityCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final est = app.estimatedCapacityWh;
    final at = app.capacityEstimatedAt;
    final when = at == null
        ? ''
        : ' · measured ${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}';
    return VoltCard(
      accentColor: VoltTokens.voltMint,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: VoltTokens.voltMint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_graph_rounded,
              color: VoltTokens.voltMint,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Auto-estimated capacity', style: VoltType.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  est == null
                      ? 'collecting ride data…'
                      : '~${est.toStringAsFixed(0)} Wh usable$when',
                  style: VoltType.caption.copyWith(color: VoltTokens.textSecondary),
                ),
              ],
            ),
          ),
          if (est != null)
            Text(
              '${est.toStringAsFixed(0)} Wh',
              style: VoltType.bodyStrong.copyWith(color: VoltTokens.voltMint),
            ),
        ],
      ),
    );
  }
}
