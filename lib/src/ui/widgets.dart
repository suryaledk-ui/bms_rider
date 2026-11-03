import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bms_manager.dart';
import 'theme.dart';

/// Signature surface container with subtle top-edge specular highlight,
/// optional ambient accent glow, and 8-pt spacing discipline.
class VoltCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? accentColor;
  final VoidCallback? onTap;
  final double borderRadius;

  const VoltCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VoltTokens.s16),
    this.margin,
    this.accentColor,
    this.onTap,
    this.borderRadius = VoltTokens.r20,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor;
    final borderColor = accent != null
        ? accent.withValues(alpha: 0.32)
        : VoltTokens.borderSubtle;

    final content = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent != null
                ? Color.lerp(VoltTokens.bgElevated, accent, 0.07)!
                : VoltTokens.bgElevated.withValues(alpha: 0.75),
            VoltTokens.bgSurface,
          ],
        ),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: VoltTokens.softShadow(accent ?? VoltTokens.voltMint),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Material(
          color: Colors.transparent,
          child: onTap != null
              ? InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: Padding(padding: padding, child: child),
                )
              : Padding(padding: padding, child: child),
        ),
      ),
    );

    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: content,
    );
  }
}

/// Eyebrow + section title row used to structure telemetry groups.
class VoltSectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final Color accent;

  const VoltSectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.icon,
    this.trailing,
    this.accent = VoltTokens.voltMint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(VoltTokens.r8),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Icon(icon, size: 15, color: accent),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: VoltType.labelMicro.copyWith(color: accent),
                ),
                const SizedBox(height: 2),
                Text(title, style: VoltType.sectionTitle),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Polished empty / disconnected state with custom vector badge and optional CTA.
class VoltEmptyState extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Color accent;

  const VoltEmptyState({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.accent = VoltTokens.voltMint,
  });

  @override
  Widget build(BuildContext context) {
    return VoltCard(
      accentColor: accent,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.24),
                  accent.withValues(alpha: 0.03),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
            ),
            child: Icon(icon, size: 30, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            eyebrow.toUpperCase(),
            style: VoltType.labelMicro.copyWith(color: accent),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: VoltType.sectionTitle.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: VoltType.body,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? Icons.bluetooth_searching, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color? color;
  final String? subtitle;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? VoltTokens.voltMint;
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VoltTokens.r16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            VoltTokens.bgElevated.withValues(alpha: 0.85),
            VoltTokens.bgSurface,
          ],
        ),
        border: Border.all(
          color: color != null
              ? accent.withValues(alpha: 0.28)
              : VoltTokens.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VoltType.labelMicro.copyWith(
                    color: VoltTokens.textSecondary,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
           FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedSwitcher(
                  duration: VoltTokens.fast,
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                  child: Text(
                    value,
                    key: ValueKey<String>(value),
                    style: VoltType.metricValue.copyWith(
                      color: color ?? VoltTokens.textPrimary,
                      fontSize: 25,
                    ),
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
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
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VoltType.caption.copyWith(fontSize: 11, color: VoltTokens.textMuted),
            ),
        ],
      ),
    );
  }
}

/// Signature Electro-Core segmented arc gauge for State of Charge (SOC) or SOH.
class SocRing extends StatelessWidget {
  final int soc;
  final double size;
  final String label;
  final String? sublabel;

  const SocRing({
    super.key,
    required this.soc,
    this.size = 150,
    this.label = 'SOC',
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = soc.clamp(0, 100);
    final color = VoltTokens.socColor(clamped);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: clamped / 100.0),
      duration: reduceMotion ? Duration.zero : VoltTokens.slow,
      curve: VoltTokens.curveOut,
      builder: (context, progress, _) {
        final shownSoc = (progress * 100).round();
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ambient core glow
              Container(
                width: size * 0.72,
                height: size * 0.72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: 0.16),
                      color.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              CustomPaint(
                size: Size.square(size),
                painter: _ElectroArcPainter(
                  progress: progress,
                  color: color,
                  trackColor: VoltTokens.bgInteractive,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: VoltType.labelMicro.copyWith(
                      color: color,
                      letterSpacing: 1.4,
                      fontSize: size * 0.072,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$shownSoc',
                        style: VoltType.displayLarge.copyWith(
                          fontSize: size * 0.25,
                          height: 1.0,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: size * 0.03),
                        child: Text(
                          '%',
                          style: VoltType.bodyStrong.copyWith(
                            fontSize: size * 0.10,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (sublabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sublabel!,
                      style: VoltType.caption.copyWith(
                        fontSize: (size * 0.075).clamp(10.0, 12.0),
                        color: VoltTokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ElectroArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _ElectroArcPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 10;
    const startAngle = 135 * math.pi / 180;
    const totalSweep = 270 * math.pi / 180;

    // Outer segmented cell ticks (24 precision ticks)
    const tickCount = 24;
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final angle = startAngle + totalSweep * t;
      final isActive = t <= progress + 0.001;
      tickPaint.color = isActive
          ? color.withValues(alpha: 0.85)
          : trackColor.withValues(alpha: 0.7);
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * (radius + 6);
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * (radius + 2);
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Main arc track
    final arcRect = Rect.fromCircle(center: center, radius: radius - 5);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.068
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(arcRect, startAngle, totalSweep, false, trackPaint);

    // Active energy arc
    if (progress > 0.005) {
      final sweep = totalSweep * progress.clamp(0.0, 1.0);
      final activePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.068
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [
            color.withValues(alpha: 0.65),
            color,
            VoltTokens.voltMintBright,
            color,
          ],
          stops: const [0.0, 0.4, 0.75, 1.0],
        ).createShader(arcRect);
      canvas.drawArc(arcRect, startAngle, sweep, false, activePaint);

      // Glowing tip node
      final endAngle = startAngle + sweep;
      final tip = center + Offset(math.cos(endAngle), math.sin(endAngle)) * (radius - 5);
      canvas.drawCircle(
        tip,
        size.width * 0.042,
        Paint()..color = color.withValues(alpha: 0.35),
      );
      canvas.drawCircle(
        tip,
        size.width * 0.022,
        Paint()..color = VoltTokens.textPrimary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ElectroArcPainter old) =>
      old.progress != progress || old.color != color;
}

class ModeChip extends StatelessWidget {
  final String mode;
  final String speed;
  const ModeChip({super.key, required this.mode, required this.speed});

  @override
  Widget build(BuildContext context) {
    final accent = VoltTokens.modeColor(mode);
    final icon = switch (mode.toLowerCase()) {
      final m when m.contains('hyper') => Icons.bolt,
      final m when m.contains('sport') => Icons.speed,
      _ => Icons.eco_outlined,
    };

    return AnimatedContainer(
      duration: VoltTokens.fast,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(VoltTokens.rPill),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: 14,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          Text(
            mode.toUpperCase(),
            style: VoltType.labelMicro.copyWith(
              color: accent,
              fontSize: 11.5,
              letterSpacing: 1.0,
            ),
          ),
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
          Text(
            speed,
            style: VoltType.caption.copyWith(
              color: VoltTokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    final (Color accent, IconData icon, String badge) = switch (state) {
      BmsState.connected => (VoltTokens.voltMint, Icons.bluetooth_connected, 'LIVE TELEMETRY'),
      BmsState.connecting => (VoltTokens.voltAmber, Icons.sync, 'HANDSHAKING'),
      BmsState.scanning => (VoltTokens.voltCyan, Icons.radar, 'SCANNING BLE'),
      BmsState.error => (VoltTokens.voltCoral, Icons.warning_amber_rounded, 'ATTENTION'),
      BmsState.idle => (VoltTokens.textSecondary, Icons.bluetooth_searching, 'TAP TO PAIR'),
    };

    return VoltCard(
      accentColor: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(VoltTokens.r12),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.7),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      badge,
                      style: VoltType.labelMicro.copyWith(color: accent, fontSize: 10.5),
                    ),
                    if (protocol != null && protocol!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: VoltTokens.bgInteractive,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: VoltTokens.borderSubtle),
                        ),
                        child: Text(
                          protocol!,
                          style: VoltType.labelMicro.copyWith(
                            fontSize: 10,
                            color: VoltTokens.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: VoltType.bodyStrong.copyWith(fontSize: 14.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: VoltTokens.bgInteractive.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(VoltTokens.rPill),
              border: Border.all(color: VoltTokens.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state == BmsState.connected ? 'Devices' : 'Scan',
                  style: VoltType.caption.copyWith(
                    color: VoltTokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right, size: 16, color: VoltTokens.textSecondary),
              ],
            ),
          ),
        ],
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
    const primary = VoltTokens.voltMint;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
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
                painter: _RadarPainter(
                  progress: disableAnimations ? 0.35 : _controller.value,
                  color: primary,
                ),
              ),
              Container(
                width: widget.size * 0.28,
                height: widget.size * 0.28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: VoltTokens.bgElevated,
                  border: Border.all(color: primary.withValues(alpha: 0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.3),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.bluetooth_searching,
                  size: widget.size * 0.15,
                  color: primary,
                ),
              ),
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

    // Crosshair axis lines
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.10);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), axisPaint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), axisPaint);

    // Static precision rings
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.20);
    canvas.drawCircle(center, maxR, ring);
    canvas.drawCircle(center, maxR * 0.68, ring);
    canvas.drawCircle(center, maxR * 0.38, ring);

    // Pulse rings expanding outward
    for (var i = 0; i < 3; i++) {
      final f = (progress + i / 3.0) % 1.0;
      final r = maxR * (0.14 + 0.86 * f);
      final a = (1.0 - f) * 0.24;
      final p = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: a);
      canvas.drawCircle(center, r, p);
    }

    // Rotating sweep beam with trailing gradient
    final sweepStart = progress * 2 * math.pi;
    const trail = 0.85;
    final beam = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.38),
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
