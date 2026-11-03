import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../range.dart';
import 'theme.dart';
import 'widgets.dart';

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
  late TextEditingController _cutoff;
  String _presetId = 'generic_48v20ah';
  String? _savedMsg;
  bool _savedOk = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _presetId = app.store.vehiclePresetId;
    _rider =
        TextEditingController(text: app.store.riderWeightKg.toStringAsFixed(0));
    _scooter = TextEditingController(
        text: app.store.scooterWeightKg.toStringAsFixed(0));
    _tyre = TextEditingController(
        text: app.store.tirePressurePsi.toStringAsFixed(0));
    _wh = TextEditingController(text: app.store.usableWh.toStringAsFixed(0));
    _cutoff = TextEditingController(
        text: app.store.cutoffSocPercent.toString());
  }

  @override
  void dispose() {
    _rider.dispose();
    _scooter.dispose();
    _tyre.dispose();
    _wh.dispose();
    _cutoff.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppController>();
    double? parse(TextEditingController c) =>
        double.tryParse(c.text.replaceAll(',', ''));

    final rider = parse(_rider);
    final scooter = parse(_scooter);
    final tyre = parse(_tyre);
    final wh = parse(_wh);
    final cutoff = int.tryParse(_cutoff.text) ?? 15;

    if (rider == null || scooter == null || tyre == null || wh == null) {
      setState(() {
        _savedMsg = 'Enter valid numbers in all fields.';
        _savedOk = false;
      });
      return;
    }
    if (rider < 30 || rider > 200 || scooter < 40 || scooter > 250) {
      setState(() {
        _savedMsg = 'Weight looks off (rider 30–200 kg, scooter 40–250 kg).';
        _savedOk = false;
      });
      return;
    }
    if (tyre < 15 || tyre > 60) {
      setState(() {
        _savedMsg = 'Tyre pressure looks off (15–60 psi).';
        _savedOk = false;
      });
      return;
    }
    if (wh < 200 || wh > 5000) {
      setState(() {
        _savedMsg = 'Battery energy looks off (200–5000 Wh).';
        _savedOk = false;
      });
      return;
    }

    await app.updateProfile(
      riderWeightKg: rider,
      scooterWeightKg: scooter,
      tirePressurePsi: tyre,
      usableWh: wh,
    );
    await app.store.setCutoffSocPercent(cutoff);
    if (!mounted) return;
    setState(() {
      _savedMsg = 'Saved — range estimates updated.';
      _savedOk = true;
    });
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
    final app = context.watch<AppController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // -- Vehicle preset --
          _SectionCard(
            icon: Icons.two_wheeler_rounded,
            accent: VoltTokens.voltMint,
            title: 'Vehicle',
            subtitle:
                'Pick your scooter — battery energy, weight and drag priors '
                'load instantly. This is the app\'s target segment.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _presetId,
                  isExpanded: true,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: VoltTokens.voltMint,
                  ),
                  dropdownColor: VoltTokens.bgElevated,
                  style: VoltType.bodyStrong,
                  decoration: const InputDecoration(labelText: 'Scooter model'),
                  items: [
                    for (final p in vehiclePresets)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          style: VoltType.bodyStrong,
                        ),
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
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: VoltTokens.bgInteractive.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: VoltTokens.borderSubtle),
                  ),
                  child: Text(
                    _presetDetail(_presetId),
                    style: VoltType.caption.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // -- Rider & scooter --
          _SectionCard(
            icon: Icons.accessibility_new_rounded,
            accent: VoltTokens.voltCyan,
            title: 'Rider & scooter',
            subtitle: 'Mass directly affects the physics range model.',
            child: Column(
              children: [
                _WeightField(
                  controller: _rider,
                  label: 'Rider weight (kg)',
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 12),
                _WeightField(
                  controller: _scooter,
                  label: 'Scooter weight (kg)',
                  icon: Icons.two_wheeler_rounded,
                ),
              ],
            ),
          ),

          // -- Tyre pressure --
          _SectionCard(
            icon: Icons.speed_rounded,
            accent: VoltTokens.voltAmber,
            title: 'Tyre pressure',
            subtitle:
                'Low pressure raises rolling loss and can trigger "less range".',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WeightField(
                  controller: _tyre,
                  label: 'Tyre pressure (psi)',
                  icon: Icons.speed_rounded,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.event_available_outlined,
                      size: 14,
                      color: VoltTokens.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      app.store.tirePressureCheckedAt == null
                          ? 'Never recorded a check'
                          : 'Last checked: ${_fmt(app.store.tirePressureCheckedAt!)}',
                      style: VoltType.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // -- Battery capacity --
          _SectionCard(
            icon: Icons.battery_charging_full_rounded,
            accent: VoltTokens.voltMint,
            title: 'Battery capacity',
            subtitle: 'Nominal pack energy (Wh). Default 960 = 48V 20Ah. '
                'Set from your pack label, or calibrate on the Battery screen.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WeightField(
                  controller: _wh,
                  label: 'Usable energy (Wh)',
                  icon: Icons.electric_bolt_rounded,
                ),
                const SizedBox(height: 12),
                _WeightField(
                  controller: _cutoff,
                  label: 'Scooter cutoff SOC (%)',
                  icon: Icons.battery_alert_rounded,
                  helper: 'How much SOC is left when your scooter stops '
                      '(e.g. 15 = stops at ~15% shown). Energy below this '
                      'is excluded from range estimates.',
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, size: 20),
              label: const Text('Save profile'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ),
          if (_savedMsg != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_savedOk ? VoltTokens.voltMint : VoltTokens.voltAmber)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        (_savedOk ? VoltTokens.voltMint : VoltTokens.voltAmber)
                            .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _savedOk
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                      size: 16,
                      color:
                          _savedOk ? VoltTokens.voltMint : VoltTokens.voltAmber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _savedMsg!,
                        style: VoltType.caption.copyWith(
                          color: _savedOk
                              ? VoltTokens.textPrimary
                              : VoltTokens.voltAmber,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
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

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return VoltCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, size: 17, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: VoltType.sectionTitle),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: VoltType.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _WeightField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? helper;

  const _WeightField({
    required this.controller,
    required this.label,
    required this.icon,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: VoltType.bodyStrong,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 18, color: VoltTokens.textMuted),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: VoltType.caption.copyWith(color: VoltTokens.textMuted),
          ),
        ],
      ],
    );
  }
}
