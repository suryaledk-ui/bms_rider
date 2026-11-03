import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: app.history.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: VoltEmptyState(
                  icon: Icons.route_rounded,
                  eyebrow: 'No rides yet',
                  title: 'Your trips live here',
                  message: 'Start a ride from the Cockpit and it will be '
                      'logged here with distance, energy and efficiency.',
                  accent: VoltTokens.voltCyan,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                const SizedBox(height: 8),
                _TripSummary(trips: app.history),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                  child: Text(
                    'RIDE HISTORY',
                    style: VoltType.labelMicro.copyWith(
                      color: VoltTokens.voltCyan,
                    ),
                  ),
                ),
                for (final trip in app.history) _TripTile(trip: trip),
              ],
            ),
    );
  }
}

class _TripSummary extends StatelessWidget {
  final List<Trip> trips;
  const _TripSummary({required this.trips});

  @override
  Widget build(BuildContext context) {
    final totalKm = trips.fold<double>(0, (s, t) => s + t.distanceKm);
    final totalWh = trips.fold<double>(0, (s, t) => s + t.whUsed);
    final totalS = trips.fold<int>(0, (s, t) => s + t.durationS.round());
    final eff = totalKm > 0.01 ? totalWh / totalKm : 0.0;

    return VoltCard(
      accentColor: VoltTokens.voltCyan,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        children: [
          Row(
            children: [
              _summaryBlock(
                  trips.length.toString(), 'TRIPS', VoltTokens.voltCyan),
              _divider(),
              _summaryBlock(
                totalKm.toStringAsFixed(1),
                'KM TOTAL',
                VoltTokens.voltMint,
              ),
              _divider(),
              _summaryBlock(
                totalWh.toStringAsFixed(0),
                'WH USED',
                VoltTokens.voltAmber,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: VoltTokens.bgInteractive.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: VoltTokens.borderSubtle),
            ),
            child: Text(
              'AVG ${eff.toStringAsFixed(1)} Wh/km · '
              '${_fmtDur(totalS)} of riding',
              textAlign: TextAlign.center,
              style: VoltType.caption.copyWith(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBlock(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: VoltType.metricValue.copyWith(color: color, fontSize: 26),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: VoltType.labelMicro.copyWith(fontSize: 9.5),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 34, color: VoltTokens.borderSubtle);
  }

  String _fmtDur(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _TripTile extends StatefulWidget {
  final Trip trip;
  const _TripTile({required this.trip});

  @override
  State<_TripTile> createState() => _TripTileState();
}

class _TripTileState extends State<_TripTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final dateFmt = DateFormat('dd MMM yyyy · HH:mm');
    final accent = VoltTokens.modeColor(_dominantMode(t));

    return VoltCard(
      accentColor: _expanded ? accent : null,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      onTap: () => setState(() => _expanded = !_expanded),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _dominantMode(t).toUpperCase(),
                  style: VoltType.labelMicro.copyWith(
                    color: accent,
                    fontSize: 9.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t.distanceKm.toStringAsFixed(2)} km',
                      style: VoltType.metricValue.copyWith(fontSize: 22),
                    ),
                    Text(
                      dateFmt.format(t.start),
                      style: VoltType.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    t.durationLabel,
                    style: VoltType.bodyStrong.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${t.whPerKm.toStringAsFixed(1)} Wh/km',
                    style: VoltType.caption.copyWith(
                      color: VoltTokens.voltMint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('avg ${t.avgSpeedKmh.toStringAsFixed(0)} km/h'),
              _chip('max ${t.maxSpeedKmh.toStringAsFixed(0)} km/h'),
              _chip('${t.whUsed.toStringAsFixed(0)} Wh'),
              _chip('SOC ${t.socStart}% → ${t.socEnd}%'),
              _chip('${t.stops} stops'),
            ],
          ),
          AnimatedSize(
            duration: VoltTokens.medium,
            curve: VoltTokens.curveOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      Container(
                        height: 1,
                        width: double.infinity,
                        color: VoltTokens.borderSubtle,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: _kv('Protocol', t.protocol)),
                          Expanded(
                            child: _kv(
                              'Regen',
                              '${t.whRegen.toStringAsFixed(0)} Wh',
                            ),
                          ),
                          Expanded(
                            child: _kv(
                              'Avg speed',
                              '${t.avgSpeedKmh.toStringAsFixed(1)} km/h',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Mode time: ${_modeSummary(t)}',
                        style: VoltType.caption.copyWith(fontSize: 12),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _dominantMode(Trip t) {
    String best = 'Eco';
    double maxSeconds = 0;
    t.modeSeconds.forEach((key, value) {
      final seconds = (value as num).toDouble();
      if (seconds > maxSeconds) {
        maxSeconds = seconds;
        best = key;
      }
    });
    return best;
  }

  String _modeSummary(Trip t) {
    final parts = <String>[];
    t.modeSeconds.forEach((k, v) {
      final s = (v as num).toDouble();
      if (s > 0) parts.add('$k ${(s / 60).round()}m');
    });
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  Widget _chip(String s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: VoltTokens.bgInteractive.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(VoltTokens.rPill),
        border: Border.all(color: VoltTokens.borderSubtle),
      ),
      child: Text(
        s,
        style: VoltType.caption.copyWith(
          fontSize: 11,
          color: VoltTokens.textSecondary,
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k.toUpperCase(),
            style: VoltType.labelMicro.copyWith(fontSize: 9.5)),
        const SizedBox(height: 3),
        Text(v, style: VoltType.bodyStrong.copyWith(fontSize: 13)),
      ],
    );
  }
}
