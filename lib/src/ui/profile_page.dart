import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../range.dart';

/// Profile / settings: vehicle preset, rider weight, scooter weight, tyre
/// pressure, battery capacity. All values apply live to the range engine.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late TextEditingController _rider;
  late TextEditingController _scooter;
  late TextEditingController _tyre;
  late TextEditingController _wh;
  String _presetId = 'generic_48v20ah';
  String? _savedMsg;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _presetId = app.store.vehiclePresetId;
    _rider = TextEditingController(text: app.store.riderWeightKg.toStringAsFixed(0));
    _scooter = TextEditingController(text: app.store.scooterWeightKg.toStringAsFixed(0));
    _tyre = TextEditingController(text: app.store.tirePressurePsi.toStringAsFixed(0));
    _wh = TextEditingController(text: app.store.usableWh.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _rider.dispose();
    _scooter.dispose();
    _tyre.dispose();
    _wh.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppController>();
    double? parse(TextEditingController c) => double.tryParse(c.text.replaceAll(',', ''));

    final rider = parse(_rider);
    final scooter = parse(_scooter);
    final tyre = parse(_tyre);
    final wh = parse(_wh);

    if (rider == null || scooter == null || tyre == null || wh == null) {
      setState(() => _savedMsg = 'Enter valid numbers in all fields.');
      return;
    }
    if (rider < 30 || rider > 200 || scooter < 40 || scooter > 250) {
      setState(() => _savedMsg = 'Weight looks off (rider 30–200 kg, scooter 40–250 kg).');
      return;
    }
    if (tyre < 15 || tyre > 60) {
      setState(() => _savedMsg = 'Tyre pressure looks off (15–60 psi).');
      return;
    }
    if (wh < 200 || wh > 5000) {
      setState(() => _savedMsg = 'Battery energy looks off (200–5000 Wh).');
      return;
    }

    await app.updateProfile(
      riderWeightKg: rider,
      scooterWeightKg: scooter,
      tirePressurePsi: tyre,
      usableWh: wh,
    );
    if (!mounted) return;
    setState(() => _savedMsg = 'Saved — range estimates updated.');
    FocusScope.of(context).unfocus();
  }

  String _presetDetail(String id) {
    for (final p in vehiclePresets) {
      if (p.id == id) return '${p.packLabel} · ${p.subtitle}';
    }
    return 'Custom settings';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final app = context.watch<AppController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // -- Vehicle preset --
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vehicle',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                    'Pick your scooter — battery energy, weight and drag priors '
                    'load instantly. This is the app\'s target segment.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _presetId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Scooter model',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final p in vehiclePresets)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final p = vehiclePresets.firstWhere((x) => x.id == v);
                      setState(() {
                        _presetId = v;
                        _scooter.text = p.scooterKg.toStringAsFixed(0);
                        _tyre.text = p.ratedPhi.toStringAsFixed(0);
                        _wh.text = p.usableWh.toStringAsFixed(0);
                      });
                      // Apply preset immediately (live update).
                      context.read<AppController>().updateProfile(preset: p);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _presetDetail(_presetId),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // -- Rider & scooter --
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rider & scooter',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                    'Mass directly affects the physics range model.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _rider,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Rider weight (kg)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _scooter,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Scooter weight (kg)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // -- Tyre pressure --
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tyre pressure',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                    'Low pressure raises rolling loss and can trigger "less range".',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tyre,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Tyre pressure (psi)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    app.store.tirePressureCheckedAt == null
                        ? 'Never recorded a check'
                        : 'Last checked: ${_fmt(app.store.tirePressureCheckedAt!)}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // -- Battery capacity --
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Battery capacity',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                    'Nominal pack energy (Wh). Default 960 = 48V 20Ah. '
                    'Set from your pack label, or calibrate on the Battery screen.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _wh,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Usable energy (Wh)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save profile'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ),
          if (_savedMsg != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _savedMsg!,
                style: TextStyle(color: _savedMsg!.startsWith('Saved') ? scheme.primary : Colors.amber),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(t.day)}/${p(t.month)}/${t.year}';
  }
}
