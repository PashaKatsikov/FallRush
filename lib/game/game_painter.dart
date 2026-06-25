import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/progression.dart';
import 'game_assets.dart';
import 'game_engine.dart';

class GamePainter extends CustomPainter {
  final GameEngine engine;
  final GameAssets assets;
  final SkinInfo skin;
  final double time;

  GamePainter({
    required this.engine,
    required this.assets,
    required this.skin,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final zone = zoneForDepth(engine.depth);
    canvas.save();
    if (engine.shake > 0.5) {
      final r = Random();
      canvas.translate(
          (r.nextDouble() - 0.5) * engine.shake,
          (r.nextDouble() - 0.5) * engine.shake);
    }

    _paintBackground(canvas, size, zone);
    _paintTube(canvas, size, zone);
    _paintCoins(canvas, size);
    _paintPowerups(canvas, size);
    _paintGates(canvas, size, zone);
    _paintSpikes(canvas, size, zone);
    _paintBlades(canvas, size);
    _paintMines(canvas, size);
    if (engine.state != GameState.gameOver) {
      _paintBall(canvas, size);
    }
    _paintParticles(canvas, size);
    canvas.restore();
  }

  // ── Background ──

  void _paintBackground(Canvas canvas, Size size, ZoneInfo zone) {
    final bg = zone.useSecondBackground ? assets.bg2 : assets.bg1;
    final rect = Offset.zero & size;

    final paint = Paint()..filterQuality = FilterQuality.medium;
    final iw = bg.width.toDouble();
    final ih = bg.height.toDouble();
    final scale = max(size.width / iw, size.height / ih);
    final dw = iw * scale;
    final dh = ih * scale;
    final dx = (size.width - dw) / 2;
    final scroll = (engine.depth * 3.0) % dh;
    for (final oy in [scroll - dh, scroll]) {
      canvas.drawImageRect(
        bg,
        Rect.fromLTWH(0, 0, iw, ih),
        Rect.fromLTWH(dx, oy, dw, dh),
        paint,
      );
    }

    // Darken + zone tint vignette.
    canvas.drawRect(
        rect, Paint()..color = const Color(0xFF05060F).withValues(alpha: 0.55));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 1.1,
          colors: [
            Colors.transparent,
            zone.wallGlow.withValues(alpha: 0.18),
            const Color(0xFF02030A).withValues(alpha: 0.75),
          ],
          stops: const [0.45, 0.8, 1.0],
        ).createShader(rect),
    );
  }

  // ── Tube walls ──

  void _paintTube(Canvas canvas, Size size, ZoneInfo zone) {
    const step = 6.0;
    final left = <Offset>[];
    final right = <Offset>[];

    for (double y = -step; y <= size.height + step; y += step) {
      final d = engine.depth + (y - engine.ballScreenY) / GameEngine.pixelsPerMeter;
      final c = engine.tubeCenter(d);
      final h = engine.tubeHalfWidth(d);
      left.add(Offset(c - h, y));
      right.add(Offset(c + h, y));
    }

    // Filled "outside the tube" regions (the walls are solid).
    final leftFill = Path()..moveTo(0, -step);
    for (final p in left) {
      leftFill.lineTo(p.dx, p.dy);
    }
    leftFill.lineTo(0, size.height + step);
    leftFill.close();

    final rightFill = Path()..moveTo(size.width, -step);
    for (final p in right) {
      rightFill.lineTo(p.dx, p.dy);
    }
    rightFill.lineTo(size.width, size.height + step);
    rightFill.close();

    final wallPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF0B0E22),
          zone.wallGlow.withValues(alpha: 0.10),
          const Color(0xFF0B0E22),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(leftFill, wallPaint);
    canvas.drawPath(rightFill, wallPaint);

    // Neon edges with glow.
    final edgeL = Path()..addPolygon(left, false);
    final edgeR = Path()..addPolygon(right, false);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = zone.accent.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawPath(edgeL, glow);
    canvas.drawPath(edgeR, glow);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = zone.accent;
    canvas.drawPath(edgeL, edge);
    canvas.drawPath(edgeR, edge);

    // Inner highlight line.
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.5);
    canvas.drawPath(edgeL, inner);
    canvas.drawPath(edgeR, inner);

    // Depth rungs (perspective rings) for speed feel. Anchored to a fixed
    // world grid (every `spacing` meters) so they scroll smoothly with the
    // tube instead of appearing frozen on screen.
    const spacing = 4.0;
    final ahead = _aheadMeters(size);
    double d = (engine.depth / spacing).floorToDouble() * spacing;
    for (; d < engine.depth + ahead; d += spacing) {
      final y = engine.depthToScreenY(d);
      if (y < -10 || y > size.height + 10) continue;
      final c = engine.tubeCenter(d);
      final h = engine.tubeHalfWidth(d);
      // Fade rungs as they approach the screen edges.
      final edgeFade =
          (1.0 - ((y / size.height) - 0.5).abs() * 2).clamp(0.0, 1.0);
      final rung = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = zone.accent.withValues(alpha: 0.05 + 0.16 * edgeFade);
      canvas.drawLine(Offset(c - h, y), Offset(c + h, y), rung);
    }
  }

  double _aheadMeters(Size size) =>
      size.height / GameEngine.pixelsPerMeter + 10;

  // ── Coins ──

  void _paintCoins(Canvas canvas, Size size) {
    for (final c in engine.coins) {
      if (c.collected) continue;
      final y = engine.depthToScreenY(c.depth);
      if (y < -30 || y > size.height + 30) continue;
      final x = engine.itemX(c.depth, c.lane);
      final r = engine.ballRadius * 0.5;
      final pulse = 0.5 + 0.5 * sin(time * 6 + c.depth);

      canvas.drawCircle(
          Offset(x, y),
          r * 2.2,
          Paint()
            ..color = const Color(0xFFFFD740).withValues(alpha: 0.25 + pulse * 0.15)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(Offset(x, y), r,
          Paint()..color = const Color(0xFFFFE57F));
      canvas.drawCircle(Offset(x, y), r * 0.6,
          Paint()..color = const Color(0xFFFFA000));
      canvas.drawCircle(
          Offset(x - r * 0.25, y - r * 0.25),
          r * 0.22,
          Paint()..color = Colors.white.withValues(alpha: 0.9));
    }
  }

  // ── Power-ups ──

  void _paintPowerups(Canvas canvas, Size size) {
    for (final p in engine.powerups) {
      if (p.collected) continue;
      final y = engine.depthToScreenY(p.depth);
      if (y < -40 || y > size.height + 40) continue;
      final x = engine.itemX(p.depth, p.lane);
      final img = switch (p.type) {
        PowerType.shield => assets.shield,
        PowerType.slowmo => assets.clock,
        PowerType.boost => assets.lightning,
      };
      final glow = switch (p.type) {
        PowerType.shield => const Color(0xFF40C4FF),
        PowerType.slowmo => const Color(0xFFB388FF),
        PowerType.boost => const Color(0xFFFFEA00),
      };
      final pulse = 0.5 + 0.5 * sin(time * 5 + p.depth);
      final d = engine.ballRadius * 2.6;
      canvas.drawCircle(
          Offset(x, y),
          d * 0.7,
          Paint()
            ..color = glow.withValues(alpha: 0.3 + pulse * 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      _drawSprite(canvas, img, Offset(x, y), d);
    }
  }

  // ── Gates ──

  void _paintGates(Canvas canvas, Size size, ZoneInfo zone) {
    for (final g in engine.gates) {
      final y = engine.depthToScreenY(g.depth);
      if (y < -40 || y > size.height + 40) continue;
      final c = engine.tubeCenter(g.depth);
      final h = engine.tubeHalfWidth(g.depth);
      final gapCenter = engine.itemX(g.depth, engine.gateGapLane(g));
      final gapHalfPx = g.gapHalf * (h - engine.ballRadius - 3);
      final barH = engine.ballRadius * 1.1;

      final leftEnd = gapCenter - gapHalfPx;
      final rightStart = gapCenter + gapHalfPx;
      const danger = Color(0xFFFF3D00);

      void bar(double x1, double x2) {
        if (x2 <= x1) return;
        final rect = Rect.fromLTRB(x1, y - barH / 2, x2, y + barH / 2);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            Paint()
              ..color = danger.withValues(alpha: 0.35)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            Paint()
              ..shader = const LinearGradient(
                colors: [Color(0xFFFF6D00), Color(0xFFFF1744)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(rect));
        // hazard stripes
        final stripe = Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..strokeWidth = 3;
        for (double sx = x1; sx < x2; sx += 12) {
          canvas.drawLine(
              Offset(sx, y - barH / 2), Offset(sx + 6, y + barH / 2), stripe);
        }
      }

      bar(c - h, leftEnd);
      bar(rightStart, c + h);

      // Opening glow edges.
      final edge = Paint()
        ..color = const Color(0xFF69F0AE).withValues(alpha: 0.8)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(leftEnd, y - barH / 2),
          Offset(leftEnd, y + barH / 2), edge);
      canvas.drawLine(Offset(rightStart, y - barH / 2),
          Offset(rightStart, y + barH / 2), edge);
    }
  }

  // ── Mines ──

  void _paintMines(Canvas canvas, Size size) {
    for (final m in engine.mines) {
      final y = engine.depthToScreenY(m.depth);
      if (y < -40 || y > size.height + 40) continue;
      final x = engine.mineX(m);
      final d = m.radius * 2.3;
      const col = Color(0xFFFF1744);
      final pulse = 0.5 + 0.5 * sin(time * 7 + m.phase);
      canvas.drawCircle(
          Offset(x, y),
          d * 0.7,
          Paint()
            ..color = col.withValues(alpha: 0.25 + pulse * 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
      // spikey body
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(m.spin);
      final spikePaint = Paint()..color = col;
      for (int i = 0; i < 8; i++) {
        final a = i * pi / 4;
        canvas.drawLine(
            Offset.zero,
            Offset(cos(a) * m.radius * 1.15, sin(a) * m.radius * 1.15),
            spikePaint
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round);
      }
      canvas.drawCircle(Offset.zero, m.radius * 0.7,
          Paint()..color = const Color(0xFF7A0014));
      canvas.drawCircle(Offset.zero, m.radius * 0.45,
          Paint()..color = Color.lerp(col, Colors.white, pulse * 0.6)!);
      canvas.restore();
    }
  }

  // ── Spikes ──

  void _paintSpikes(Canvas canvas, Size size, ZoneInfo zone) {
    for (final s in engine.spikes) {
      final y = engine.depthToScreenY(s.depth);
      if (y < -40 || y > size.height + 40) continue;
      final c = engine.tubeCenter(s.depth);
      final h = engine.tubeHalfWidth(s.depth);
      final len = h * engine.spikeProtrude(s);
      final spikeH = engine.ballRadius * 2.4;

      canvas.save();
      if (s.rightSide) {
        canvas.translate(c + h, y);
        canvas.rotate(pi / 2); // point left/inward
      } else {
        canvas.translate(c - h, y);
        canvas.rotate(-pi / 2);
      }
      // sprite drawn with its tip toward +? draw centered, width=spikeH, height=len*2
      final img = assets.spike;
      final iw = img.width.toDouble();
      final ih = img.height.toDouble();
      final dst = Rect.fromCenter(
          center: Offset(0, len * 0.5), width: spikeH, height: len * 1.1);
      canvas.drawImageRect(
          img, Rect.fromLTWH(0, 0, iw, ih), dst, Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
    }
  }

  // ── Blades ──

  void _paintBlades(Canvas canvas, Size size) {
    for (final b in engine.blades) {
      final y = engine.depthToScreenY(b.depth);
      if (y < -40 || y > size.height + 40) continue;
      final lane = b.lane + sin(time * b.driftFreq + b.phase) * b.driftAmp;
      final x = engine.itemX(b.depth, lane.clamp(-0.85, 0.85));
      final d = b.radius * 2.4;
      canvas.drawCircle(
          Offset(x, y),
          d * 0.6,
          Paint()
            ..color = const Color(0xFFFF1744).withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin);
      _drawSprite(canvas, assets.blade, Offset.zero, d);
      canvas.restore();
    }
  }

  // ── Ball ──

  void _paintBall(Canvas canvas, Size size) {
    final x = engine.ballX;
    final y = engine.ballScreenY;
    final r = engine.ballRadius;
    final d = r * 2.4;

    // Trail
    final trailColor = skin.id == 'rainbow'
        ? HSVColor.fromAHSV(1, (time * 90) % 360, 0.9, 1).toColor()
        : skin.tint;
    for (int i = 1; i <= 5; i++) {
      final ty = y + i * 9.0;
      canvas.drawCircle(
          Offset(x, ty),
          r * (1 - i * 0.13),
          Paint()
            ..color = trailColor.withValues(alpha: 0.18 - i * 0.03)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }

    // Glow (red as it heats)
    final glowColor = Color.lerp(trailColor, const Color(0xFFFF3D00), engine.heat)!;
    canvas.drawCircle(
        Offset(x, y),
        d * (0.75 + engine.heat * 0.3),
        Paint()
          ..color = glowColor.withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + engine.heat * 10));

    // Base ball sprite
    _drawSprite(canvas, assets.ball, Offset(x, y), d);

    // Skin tint overlay
    if (skin.tintStrength > 0 || skin.id == 'rainbow') {
      final tint = skin.id == 'rainbow'
          ? HSVColor.fromAHSV(1, (time * 90) % 360, 0.85, 1).toColor()
          : skin.tint;
      final strength = skin.id == 'rainbow' ? 0.5 : skin.tintStrength;
      _drawSprite(canvas, assets.ball, Offset(x, y), d,
          tint: tint, tintAlpha: strength);
    }

    // Overheat sprite crossfade
    if (engine.heat > 0.02) {
      _drawSprite(canvas, assets.ballRed, Offset(x, y), d, alpha: engine.heat);
    }

    // Shield ring
    if (engine.shieldTimer > 0) {
      final blink = engine.shieldTimer < 1.2
          ? (0.4 + 0.6 * sin(time * 18).abs())
          : 1.0;
      canvas.drawCircle(
          Offset(x, y),
          d * 0.72,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFF40C4FF).withValues(alpha: 0.85 * blink)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
  }

  // ── Particles ──

  void _paintParticles(Canvas canvas, Size size) {
    for (final p in engine.particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
          Offset(p.x, p.y),
          p.size * a,
          Paint()
            ..color = p.color.withValues(alpha: a)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
  }

  // ── Helpers ──

  void _drawSprite(Canvas canvas, ui.Image img, Offset center, double diameter,
      {double alpha = 1.0, Color? tint, double tintAlpha = 0.0}) {
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final scale = diameter / max(iw, ih);
    final dw = iw * scale;
    final dh = ih * scale;
    final dst = Rect.fromCenter(
        center: center, width: dw, height: dh);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (alpha < 1.0) paint.color = Colors.white.withValues(alpha: alpha);
    if (tint != null) {
      paint.colorFilter =
          ColorFilter.mode(tint.withValues(alpha: tintAlpha), BlendMode.srcATop);
    }
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), dst, paint);
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
