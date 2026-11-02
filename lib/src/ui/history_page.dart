import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../models.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: app.history.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.route, size: 48, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('No trips yet', style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: app.history.length,
              itemBuilder: (_, i) {
                final t = app.history[i];
                return _TripTile(trip: t);
              },
            ),
    );
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
    final scheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('dd MMM yyyy · HH:mm');

    return Card(
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t.distanceKm.toStringAsFixed(2)} km',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface),
                        ),
                        Text(
                          dateFmt.format(t.start),
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(t.durationLabel, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
                      Text(
                        '${t.whPerKm.toStringAsFixed(1)} Wh/km',
                        style: TextStyle(fontSize: 12, color: scheme.primary),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _chip('avg ${t.avgSpeedKmh.toStringAsFixed(0)} km/h'),
                  _chip('max ${t.maxSpeedKmh.toStringAsFixed(0)} km/h'),
                  _chip('${t.whUsed.toStringAsFixed(0)} Wh'),
                  _chip('SOC ${t.socStart}% → ${t.socEnd}%'),
                  _chip('${t.stops} stops'),
                ],
              ),
              if (_expanded) ...[
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(child: _kv('Protocol', t.protocol)),
                    Expanded(child: _kv('Regen', '${t.whRegen.toStringAsFixed(0)} Wh')),
                    Expanded(child: _kv('Avg speed', '${t.avgSpeedKmh.toStringAsFixed(1)} km/h')),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Mode time: ${_modeSummary(t)}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _modeSummary(Trip t) {
    final parts = <String>[];
    t.modeSeconds.forEach((k, v) {
      if (v > 0) parts.add('$k ${(v / 60).round()}m');
    });
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  Widget _chip(String s) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2530),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(s, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
    );
  }

  Widget _kv(String k, String v) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
