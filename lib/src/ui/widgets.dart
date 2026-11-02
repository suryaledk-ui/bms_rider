import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bms_manager.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color? color;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color ?? scheme.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: color ?? scheme.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SocRing extends StatelessWidget {
  final int soc;
  final double size;

  const SocRing({super.key, required this.soc, this.size = 150});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = soc > 50
        ? const Color(0xFF00E5A0)
        : soc > 20
            ? const Color(0xFFFFB300)
            : const Color(0xFFFF5252);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: soc / 100.0,
              strokeWidth: 10,
              backgroundColor: const Color(0xFF1C2530),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$soc%',
                style: TextStyle(
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              Text('SOC', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class ModeChip extends StatelessWidget {
  final String mode;
  final String speed;
  const ModeChip({super.key, required this.mode, required this.speed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$mode · $speed',
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class ConnectionBanner extends StatelessWidget {
  final BmsState state;
  final String status;
  final String? protocol;
  final VoidCallback onTap;

  const ConnectionBanner({
    super.key,
    required this.state,
    required this.status,
    required this.protocol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color c, IconData ic) = switch (state) {
      BmsState.connected => (const Color(0xFF00E5A0), Icons.link),
      BmsState.connecting || BmsState.scanning => (const Color(0xFFFFB300), Icons.sync),
      BmsState.error => (const Color(0xFFFF5252), Icons.error_outline),
      BmsState.idle => (scheme.onSurfaceVariant, Icons.bluetooth_disabled),
    };
    return InkWell(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(ic, color: c),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (protocol != null)
                      Text(
                        protocol!,
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated bluetooth sonar used while scanning for the scooter BMS.
class ScanRadar extends StatefulWidget {
  final double size;
  const ScanRadar({super.key, this.size = 180});

  @override
  State<ScanRadar> createState() => _ScanRadarState();
}

class _ScanRadarState extends State<ScanRadar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _RadarPainter(progress: _controller.value, color: primary),
              ),
              Icon(Icons.bluetooth_searching, size: widget.size * 0.22, color: primary),
            ],
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // Static rings
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.22);
    canvas.drawCircle(center, maxR, ring);
    canvas.drawCircle(center, maxR * 0.66, ring);
    canvas.drawCircle(center, maxR * 0.33, ring);

    // Pulse rings expanding outward
    for (var i = 0; i < 3; i++) {
      final f = (progress + i / 3.0) % 1.0;
      final r = maxR * (0.12 + 0.88 * f);
      final a = (1.0 - f) * 0.30;
      final p = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: a);
      canvas.drawCircle(center, r, p);
    }

    // Rotating sweep beam with trailing gradient
    final sweepStart = progress * 2 * math.pi;
    const trail = 0.7;
    final beam = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.40),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
        startAngle: sweepStart - trail,
        endAngle: sweepStart,
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR),
      sweepStart - trail,
      trail,
      true,
      beam,
    );

    // Leading edge
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawLine(
      center,
      center + Offset(math.cos(sweepStart), math.sin(sweepStart)) * maxR,
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.progress != progress || old.color != color;
}
