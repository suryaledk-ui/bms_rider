import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bms_manager.dart';
import '../controller.dart';
import '../models.dart';
import '../range.dart';
import 'log_page.dart';
import 'profile_page.dart';
import 'ride_page.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _scanning = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Drives the "updated Xs ago" freshness micro-text between telemetry
    // frames / watchdog notifications (both arrive at ~5s granularity).
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final bms = app.bms;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 6,
        title: const _BrandTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Profile & settings',
            onPressed: () =>
                Navigator.of(context).push(voltPageRoute(const ProfilePage())),
          ),
          IconButton(
            icon: const Icon(Icons.terminal_rounded),
            tooltip: 'Scan logs',
            onPressed: () =>
                Navigator.of(context).push(voltPageRoute(const LogPage())),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rescan',
            onPressed: () => app.requestPermissionsAndScan(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => app.requestPermissionsAndScan(),
        color: VoltTokens.voltMint,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const SizedBox(height: 4),
            ConnectionBanner(
              state: bms.state,
              status: bms.status,
              protocol: bms.proto?.name,
              dataFresh: bms.dataFresh,
              onTap: () => _showScanSheet(context, app),
            ),
            if (bms.state == BmsState.scanning) ..._scanningPanel(),
            if (bms.state != BmsState.scanning && bms.candidates.isNotEmpty)
              ..._candidateList(app),
            if (bms.latest != null) ..._liveSection(context, app),
            if (bms.latest == null && bms.state == BmsState.idle)
              _idleEmptyState(app),
            if (app.lastDiagnostic != null && app.lastDiagnostic!.lessRange)
              _tyreNudgeCard(context, app),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Brand & scanning states
  // ---------------------------------------------------------------------

  List<Widget> _scanningPanel() {
    return [
      VoltCard(
        accentColor: VoltTokens.voltCyan,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          children: [
            const ScanRadar(size: 190),
            const SizedBox(height: 18),
            Text(
              'LISTENING FOR YOUR SCOOTER',
              style: VoltType.labelMicro.copyWith(color: VoltTokens.voltCyan),
            ),
            const SizedBox(height: 6),
            Text(
              'Keep the scooter ON and nearby',
              style: VoltType.body.copyWith(fontSize: 13),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _idleEmptyState(AppController app) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: VoltEmptyState(
        icon: Icons.bluetooth_searching_rounded,
        eyebrow: 'Ready when you are',
        title: 'No scooter linked yet',
        message: 'Turn your scooter ON, keep it near the phone, then scan. '
            'Location permission is only needed for ride tracking — '
            'not for connecting.',
        actionLabel: 'Scan for BMS',
        actionIcon: Icons.radar_rounded,
        onAction: () => app.requestPermissionsAndScan(),
      ),
    );
  }

  List<Widget> _candidateList(AppController app) {
    final bms = app.bms;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(
          '${bms.candidates.length} DEVICE${bms.candidates.length == 1 ? '' : 'S'} FOUND',
          style: VoltType.labelMicro.copyWith(color: VoltTokens.voltMint),
        ),
      ),
      ...bms.candidates.map((c) {
        final rssiColor = c.rssi >= -60
            ? VoltTokens.voltMint
            : c.rssi >= -75
                ? VoltTokens.voltAmber
                : VoltTokens.voltCoral;
        return VoltCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: rssiColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: rssiColor.withValues(alpha: 0.35)),
                ),
                child: Icon(
                  Icons.signal_cellular_alt_rounded,
                  color: rssiColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VoltType.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          c.guess,
                          style: VoltType.caption.copyWith(
                            color: VoltTokens.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${c.rssi} dBm',
                          style: VoltType.caption.copyWith(
                            color: rssiColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () async {
                  await bms.connectTo(c);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: VoltTokens.voltMint.withValues(alpha: 0.12),
                  foregroundColor: VoltTokens.voltMint,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('PAIR'),
              ),
            ],
          ),
        );
      }),
    ];
  }

  // ---------------------------------------------------------------------
  // Connected / live section
  // ---------------------------------------------------------------------

  List<Widget> _liveSection(BuildContext context, AppController app) {
    final bms = app.bms;
    final t = bms.latest!;
    final speed = app.currentSpeedKmh;
    final mode = modeForSpeed(speed);
    final report = app.range.report(t, speed, 0);
    final socColor = VoltTokens.socColor(t.socPercent);
    final riding = app.ride != null;
    final dataFresh = bms.dataFresh;

    return [
      // ---- Hero SOC block ----
      VoltCard(
        accentColor: socColor,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _packTagRow(t: t),
                      const SizedBox(height: 10),
                      Center(
                        child: LiveBadge(
                          fresh: dataFresh,
                          ageSeconds: bms.dataAgeSeconds,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: ModeChip(
                          mode: modeName(mode),
                          speed: '${speed.toStringAsFixed(0)} km/h',
                        ),
                      ),
                      if (app.weather != null) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            '${app.weather!.tempC.toStringAsFixed(0)}°C · wind '
                            '${app.weather!.windSpeedKmh.toStringAsFixed(0)} km/h',
                            style: VoltType.caption.copyWith(
                              color: VoltTokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Center(
                        child: _signalChip(bms.rssi),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  opacity: dataFresh ? 1.0 : 0.55,
                  duration: VoltTokens.medium,
                  child: SocRing(
                    soc: t.socPercent,
                    size: 152,
                    sublabel: '${t.voltageV.toStringAsFixed(1)} V',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (app.isCharging) ...[
        const SizedBox(height: 10),
        _chargingCard(app),
      ],
      const SizedBox(height: 10),

      // ---- Live electrical readings ----
      const VoltSectionHeader(
        eyebrow: 'Live pack',
        title: 'Electrical readings',
        icon: Icons.bolt_rounded,
      ),
      AnimatedOpacity(
        opacity: dataFresh ? 1.0 : 0.55,
        duration: VoltTokens.medium,
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          children: [
            StatCard(
              label: 'Voltage',
              value: t.voltageV.toStringAsFixed(1),
              unit: 'V',
              icon: Icons.bolt_rounded,
              color: VoltTokens.voltCyan,
            ),
            StatCard(
              label: 'Current',
              value: t.currentA.toStringAsFixed(1),
              unit: 'A',
              icon: Icons.electric_bolt_rounded,
              color: t.currentA > 0 ? VoltTokens.voltAmber : VoltTokens.voltMint,
              subtitle: t.currentA > 0 ? 'discharging' : 'regen / charging',
            ),
            StatCard(
              label: 'Power',
              value: t.powerW.abs().toStringAsFixed(0),
              unit: 'W',
              icon: Icons.flash_on_rounded,
              color: t.powerW > 0 ? VoltTokens.voltAmber : VoltTokens.voltMint,
            ),
            StatCard(
              label: 'Cells',
              value: t.cellVolts.isEmpty
                  ? '—'
                  : '${t.cellMinV.toStringAsFixed(2)}–${t.cellMaxV.toStringAsFixed(2)}',
              unit: 'V',
              icon: Icons.grid_view_rounded,
              color: VoltTokens.voltMint,
              subtitle:
                  t.cellVolts.isEmpty ? null : '${t.cellVolts.length} series',
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),

      // ---- Live overview strip ----
      _liveOverviewCard(t),
      const SizedBox(height: 10),

      // ---- Range forecast ----
      const VoltSectionHeader(
        eyebrow: 'Range forecast',
        title: 'What your pack gives you',
        icon: Icons.route_rounded,
      ),
      _rangeCard(report: report, mode: mode),
      const SizedBox(height: 10),

      // ---- Ride controls ----
      if (!riding)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              voltPageRoute(const RidePage()),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: const Text('Start ride'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: VoltTokens.voltMint,
              foregroundColor: const Color(0xFF031B11),
            ),
          ),
        )
      else
        VoltCard(
          accentColor: VoltTokens.voltMint,
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          onTap: () => Navigator.of(context).push(
            voltPageRoute(const RidePage()),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: VoltTokens.voltMint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_bike_rounded,
                  color: VoltTokens.voltMint,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ride in progress',
                      style: VoltType.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(app.ride!.distanceM / 1000).toStringAsFixed(2)} km · '
                      '${app.ride!.durationLabel}',
                      style: VoltType.caption,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: VoltTokens.textSecondary,
              ),
            ],
          ),
        ),
      if (app.lastDiagnostic != null) ...[
        const SizedBox(height: 8),
        _diagnosticCard(context, app.lastDiagnostic!),
      ],
    ];
  }

  // ---------------------------------------------------------------------
  // Signal chip & charging card
  // ---------------------------------------------------------------------

  Widget _signalChip(int? rssi) {
    if (rssi == null) return const SizedBox.shrink();
    final color = rssi >= -60
        ? VoltTokens.voltMint
        : rssi >= -75
            ? VoltTokens.voltAmber
            : VoltTokens.voltCoral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.signal_cellular_alt_rounded, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            '$rssi dBm',
            style: VoltType.caption.copyWith(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chargingCard(AppController app) {
    final t = app.bms.latest;
    final eta = app.chargeEtaMinutes;
    final etaLabel = eta == null
        ? 'measuring rate…'
        : eta >= 60
            ? '~${(eta / 60).floor()}h ${eta % 60}m to full'
            : '~$eta min to full';

    return VoltCard(
      accentColor: VoltTokens.voltMint,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const _ChargingBolt(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Charging', style: VoltType.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  t == null ? etaLabel : '${t.socPercent}% · $etaLabel',
                  style: VoltType.caption.copyWith(color: VoltTokens.textSecondary),
                ),
              ],
            ),
          ),
          if (t != null)
            Text(
              '${t.socPercent}%',
              style: VoltType.metricValue.copyWith(color: VoltTokens.voltMint),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Live overview strip
  // ---------------------------------------------------------------------

  Widget _liveOverviewCard(Telemetry t) {
    final currentColor =
        t.currentA > 0 ? VoltTokens.voltAmber : VoltTokens.voltMint;
    final powerColor =
        t.powerW > 0 ? VoltTokens.voltAmber : VoltTokens.voltMint;
    final tempsLabel = t.tempsC.isEmpty
        ? '—'
        : t.tempsC.map((c) => c.toStringAsFixed(1)).join(' / ');

    return VoltCard(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights_rounded,
                size: 16,
                color: VoltTokens.voltMint,
              ),
              const SizedBox(width: 8),
              Text(
                'LIVE OVERVIEW',
                style: VoltType.labelMicro.copyWith(
                  color: VoltTokens.voltMint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _liveMetric(
                  label: 'Pack voltage',
                  value: t.voltageV.toStringAsFixed(1),
                  unit: 'V',
                  color: VoltTokens.voltMint,
                  now: true,
                ),
              ),
              Expanded(
                child: _liveMetric(
                  label: 'Current',
                  value: t.currentA.toStringAsFixed(1),
                  unit: 'A',
                  color: currentColor,
                ),
              ),
              Expanded(
                child: _liveMetric(
                  label: 'Power',
                  value: t.powerW.abs().toStringAsFixed(0),
                  unit: 'W',
                  color: powerColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _liveMetric(
                  label: t.cellVolts.isEmpty
                      ? 'Cells'
                      : 'Cells · ${t.cellVolts.length}S',
                  value: t.cellVolts.isEmpty
                      ? '—'
                      : '${t.cellMinV.toStringAsFixed(2)}–${t.cellMaxV.toStringAsFixed(2)}',
                  unit: t.cellVolts.isEmpty ? null : 'V',
                  color: VoltTokens.voltMint,
                ),
              ),
              Expanded(
                child: _liveMetric(
                  label: 'Pack temp',
                  value: tempsLabel,
                  unit: t.tempsC.isEmpty ? null : '°C',
                  color: VoltTokens.voltCyan,
                ),
              ),
              Expanded(
                child: _liveMetric(
                  label: 'Residual',
                  value: t.residualAh.toStringAsFixed(2),
                  unit: 'Ah',
                  color: VoltTokens.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _liveMetric({
    required String label,
    required String value,
    String? unit,
    Color? color,
    bool now = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (now) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: VoltTokens.voltMint,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: VoltTokens.voltMint.withValues(alpha: 0.6),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VoltType.labelMicro.copyWith(
                  fontSize: 9.5,
                  color: VoltTokens.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: VoltType.metricValue.copyWith(
                  fontSize: 18,
                  color: color ?? VoltTokens.textPrimary,
                ),
              ),
              if (unit != null && unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: VoltType.caption.copyWith(
                    color: VoltTokens.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _packTagRow({required Telemetry t}) {
    final items = <Widget>[
      _packTag('${t.cellVolts.length} S', Icons.grid_view_rounded),
      const SizedBox(width: 8),
      _packTag(
          '${t.nominalAh.toStringAsFixed(1)} Ah', Icons.battery_5_bar_rounded),
      const SizedBox(width: 8),
      _packTag(cycleLabel(t), Icons.autorenew_rounded),
    ];
    return Wrap(spacing: 0, runSpacing: 8, children: items);
  }

  Widget _packTag(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: VoltTokens.bgInteractive.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VoltTokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: VoltTokens.textMuted),
          const SizedBox(width: 4),
          Text(
            text,
            style: VoltType.labelMicro.copyWith(
              fontSize: 10,
              color: VoltTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String cycleLabel(Telemetry t) =>
      t.cycleCount > 0 ? '${t.cycleCount} cycles' : 'new pack';

  // ---------------------------------------------------------------------
  // Range card
  // ---------------------------------------------------------------------

  Widget _rangeCard({required RangeReport report, required RideMode mode}) {
    final rows =
        <({String label, String sub, double km, bool active, bool now})>[
      (
        label: 'Eco',
        sub: '10–30 km/h',
        km: report.ecoKm,
        active: mode == RideMode.eco,
        now: false
      ),
      (
        label: 'Sports',
        sub: '30–42 km/h',
        km: report.sportsKm,
        active: mode == RideMode.sports,
        now: false
      ),
      (
        label: 'Hyper',
        sub: '42+ km/h',
        km: report.hyperKm,
        active: mode == RideMode.hyper,
        now: false
      ),
      (
        label: 'Now',
        sub: 'current speed',
        km: report.liveKm,
        active: false,
        now: true
      ),
    ];
    final maxKm =
        rows.fold<double>(1.0, (m, r) => mathMax(m, r.km.isFinite ? r.km : 0));

    return VoltCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          for (final r in rows) _rangeRow(r, maxKm),
          const SizedBox(height: 4),
          Text(
            'Estimate from pack energy + your riding style — refines automatically as you ride.',
            style: VoltType.caption.copyWith(
              fontSize: 11,
              color: VoltTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  double mathMax(double a, double b) => a > b ? a : b;

  Widget _rangeRow(
    ({String label, String sub, double km, bool active, bool now}) r,
    double maxKm,
  ) {
    final color = r.now
        ? VoltTokens.voltMint
        : r.active
            ? VoltTokens.voltMint
            : VoltTokens.textMuted;
    final fraction = (r.km.isFinite ? r.km : 0.0) / maxKm;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                r.label.toUpperCase(),
                style: VoltType.labelMicro.copyWith(
                  color: r.now || r.active
                      ? VoltTokens.voltMint
                      : VoltTokens.textSecondary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.sub,
                  style: VoltType.caption.copyWith(fontSize: 11.5),
                ),
              ),
              Text(
                r.km.isFinite ? '${r.km.toStringAsFixed(0)} km' : '—',
                style: VoltType.bodyStrong.copyWith(
                  color: r.now ? VoltTokens.textPrimary : color,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                children: [
                  Container(
                    height: 5,
                    width: width,
                    decoration: BoxDecoration(
                      color: VoltTokens.bgInteractive,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  AnimatedContainer(
                    duration: VoltTokens.medium,
                    curve: VoltTokens.curveOut,
                    height: 5,
                    width: width * fraction.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.65),
                          r.now ? VoltTokens.voltMintBright : color,
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Diagnostics & tyre nudges
  // ---------------------------------------------------------------------

  Widget _diagnosticCard(BuildContext context, DiagnosticResult d) {
    final accent = d.lessRange ? VoltTokens.voltAmber : VoltTokens.voltMint;
    return VoltCard(
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                d.lessRange
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  d.title,
                  style: VoltType.sectionTitle,
                ),
              ),
            ],
          ),
          if (d.hints.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final h in d.hints)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '·',
                      style: VoltType.bodyStrong.copyWith(color: accent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child:
                          Text(h, style: VoltType.body.copyWith(fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tyreNudgeCard(BuildContext context, AppController app) {
    final lastCheck = app.store.tirePressureCheckedAt;
    final overdue =
        lastCheck == null || DateTime.now().difference(lastCheck).inDays > 30;
    if (!overdue) return const SizedBox.shrink();

    return VoltCard(
      accentColor: VoltTokens.voltAmber,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, color: VoltTokens.voltAmber, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tyre pressure may be low',
                  style: VoltType.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Less range was detected and tyre pressure hasn\'t been checked '
            '${lastCheck == null ? 'yet' : 'in 30+ days'}. A quick check can '
            'restore range.',
            style: VoltType.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: () => app.updateProfile(
                    tirePressurePsi: app.store.tirePressurePsi),
                style: FilledButton.styleFrom(
                  backgroundColor: VoltTokens.voltAmber.withValues(alpha: 0.14),
                  foregroundColor: VoltTokens.voltAmber,
                ),
                child: const Text('Checked now'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  voltPageRoute(const ProfilePage()),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: VoltTokens.textSecondary,
                ),
                child: const Text('Set pressure'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Scan bottom sheet
  // ---------------------------------------------------------------------

  Future<void> _showScanSheet(BuildContext context, AppController app) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: VoltTokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: VoltTokens.borderStrong,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: VoltTokens.voltMint.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  VoltTokens.voltMint.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Icon(
                            Icons.bluetooth_searching_rounded,
                            color: VoltTokens.voltMint,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connect scooter',
                              style:
                                  VoltType.sectionTitle.copyWith(fontSize: 18),
                            ),
                            Text(
                              'Pair over BLE with the BMS pack',
                              style: VoltType.caption,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Turn the scooter ON, keep it near the phone, then scan. '
                      'Location permission is NOT needed for connecting — '
                      'only for ride tracking.',
                      style: VoltType.body.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        setSheetState(() => _scanning = true);
                        await app.requestPermissionsAndScan();
                        if (ctx.mounted) setSheetState(() => _scanning = false);
                      },
                      icon: Icon(
                        _scanning ? Icons.radar_rounded : Icons.radar_rounded,
                        size: 20,
                      ),
                      label: Text(_scanning ? 'Scanning…' : 'Scan for BMS'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_scanning)
                      Center(
                        child: Column(
                          children: const [
                            ScanRadar(size: 120),
                            SizedBox(height: 12),
                            Text(
                              'Looking for your scooter…',
                              style: VoltType.body,
                            ),
                          ],
                        ),
                      )
                    else if (app.bms.candidates.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: VoltTokens.bgElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: VoltTokens.borderSubtle),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: VoltTokens.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'No BMS found yet.',
                              style: VoltType.body.copyWith(fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else
                      SizedBox(
                        height: 250,
                        child: ListView.builder(
                          itemCount: app.bms.candidates.length,
                          itemBuilder: (_, i) {
                            final c = app.bms.candidates[i];
                            final rssiColor = c.rssi >= -60
                                ? VoltTokens.voltMint
                                : c.rssi >= -75
                                    ? VoltTokens.voltAmber
                                    : VoltTokens.voltCoral;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: VoltTokens.bgElevated,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: VoltTokens.borderSubtle),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.battery_charging_full_rounded,
                                    color: VoltTokens.voltMint,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: VoltType.bodyStrong,
                                        ),
                                        Text(
                                          '${c.guess} · ${c.id} · ${c.rssi} dBm',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: VoltType.caption.copyWith(
                                            fontSize: 11,
                                            color: rssiColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: () async {
                                      await app.bms.connectTo(c);
                                      if (ctx.mounted) {
                                        Navigator.of(ctx).pop();
                                      }
                                    },
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      backgroundColor: VoltTokens.voltMint
                                          .withValues(alpha: 0.12),
                                      foregroundColor: VoltTokens.voltMint,
                                    ),
                                    child: const Text('PAIR'),
                                  ),
                                ],
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

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                VoltTokens.voltMint.withValues(alpha: 0.85),
                VoltTokens.voltMintBright,
              ],
            ),
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: VoltTokens.voltMint.withValues(alpha: 0.35),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
          child: const Icon(
            Icons.bolt_rounded,
            color: Color(0xFF031B11),
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        const Text('BMS Rider'),
      ],
    );
  }
}

/// Pulsing bolt used in the charging status card.
class _ChargingBolt extends StatefulWidget {
  const _ChargingBolt();

  @override
  State<_ChargingBolt> createState() => _ChargingBoltState();
}

class _ChargingBoltState extends State<_ChargingBolt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: VoltTokens.voltMint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
        child: const Icon(
          Icons.bolt_rounded,
          color: VoltTokens.voltMint,
          size: 26,
        ),
      ),
    );
  }
}
