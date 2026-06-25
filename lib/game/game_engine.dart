import 'dart:math';
import 'dart:ui';

enum GameState { menu, playing, paused, gameOver }

enum PowerType { shield, slowmo, boost }

class Obstacle {
  final double depth;
  final double depthHalf;
  Obstacle(this.depth, this.depthHalf);
}

class Spike extends Obstacle {
  final bool rightSide;
  final double protrudeFrac;
  final bool pulsing;
  Spike(super.depth, super.depthHalf, this.rightSide, this.protrudeFrac,
      {this.pulsing = false});
}

/// A bar spanning the tube with a single opening the ball must pass through.
class Gate extends Obstacle {
  final double gapLane; // center of the opening, -1..1
  final double gapHalf; // half-width of opening as fraction of inner half
  final double driftAmp;
  final double driftFreq;
  final double phase;
  Gate(super.depth, super.depthHalf, this.gapLane, this.gapHalf,
      this.driftAmp, this.driftFreq, this.phase);
}

/// A drifting energy mine that floats inside the tube.
class Mine extends Obstacle {
  final double lane;
  final double driftAmp;
  final double driftFreq;
  final double phase;
  final double radius;
  double spin = 0;
  Mine(super.depth, super.depthHalf, this.lane, this.driftAmp, this.driftFreq,
      this.phase, this.radius);
}

class Blade extends Obstacle {
  final double lane;
  final double driftAmp;
  final double driftFreq;
  final double phase;
  final double radius;
  double spin = 0;
  Blade(super.depth, super.depthHalf, this.lane, this.driftAmp, this.driftFreq,
      this.phase, this.radius);
}

class Coin {
  final double depth;
  final double lane;
  bool collected = false;
  Coin(this.depth, this.lane);
}

class PowerUp {
  final double depth;
  final double lane;
  final PowerType type;
  bool collected = false;
  PowerUp(this.depth, this.lane, this.type);
}

class Particle {
  double x, y, vx, vy, life, maxLife, size;
  Color color;
  Particle(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color)
      : maxLife = life;
}

class GameEngine {
  final Random _rng = Random();

  double screenWidth = 0;
  double screenHeight = 0;

  static const double pixelsPerMeter = 17.0;

  GameState state = GameState.menu;

  // Run stats
  double depth = 0; // meters descended
  int score = 0;
  int coinsCollected = 0;
  int shieldsGrabbed = 0;
  double multiplier = 1.0;

  // Records / wallet (mirrored from storage by GameScreen)
  int highScore = 0;
  int bestDistance = 0;

  // Ball
  double ballX = 0;
  double targetX = 0;
  double ballVX = 0;
  double heat = 0; // 0..1
  double ballRadius = 18;

  // Power timers (seconds)
  double shieldTimer = 0;
  double slowmoTimer = 0;
  double boostTimer = 0;

  // Upgrade-derived params
  double heatGainMult = 1.0;
  double shieldDuration = 4.0;
  double slowmoDuration = 3.0;
  double magnetRange = 0;
  double coinValueMult = 1.0;
  double startShield = 0;

  // World
  final List<Spike> spikes = [];
  final List<Blade> blades = [];
  final List<Gate> gates = [];
  final List<Mine> mines = [];
  final List<Coin> coins = [];
  final List<PowerUp> powerups = [];
  final List<Particle> particles = [];
  double _genCursor = 0;

  double menuTime = 0;
  double deathTimer = 0;
  double shake = 0;
  double timeScale = 1.0; // smoothed slow-mo factor for rendering feel

  // last-collected flash
  PowerType? lastPickup;
  double pickupFlash = 0;

  double get ballScreenY => screenHeight * 0.6;

  int get distance => depth.round();
  int get coinReward => (coinsCollected * coinValueMult).round();

  void setSize(double w, double h) {
    screenWidth = w;
    screenHeight = h;
    ballRadius = min(w, h) * 0.035;
    if (state == GameState.menu) {
      ballX = w / 2;
      targetX = w / 2;
    }
  }

  void applyUpgrades({
    required int heatShieldLvl,
    required int shieldDurationLvl,
    required int magnetLvl,
    required int coinValueLvl,
    required int slowmoLvl,
    required int startShieldLvl,
  }) {
    heatGainMult = (1.0 - 0.13 * heatShieldLvl).clamp(0.3, 1.0);
    shieldDuration = 4.0 + shieldDurationLvl * 1.2;
    magnetRange = magnetLvl * 55.0;
    coinValueMult = 1.0 + coinValueLvl * 0.15;
    slowmoDuration = 3.0 + slowmoLvl * 1.0;
    startShield = startShieldLvl * 1.5;
  }

  // ── Tube geometry (functions of world depth, in pixels) ──

  double tubeCenter(double d) {
    final w = screenWidth;
    final wind = sin(d * 0.16) * 0.26 + sin(d * 0.34 + 1.7) * 0.11;
    return w * 0.5 + wind * w * 0.5;
  }

  double tubeHalfWidth(double d) {
    final w = screenWidth;
    final difficulty = (d / 2200).clamp(0.0, 1.0);
    final base = w * (0.36 - 0.13 * difficulty);
    final pinch = (sin(d * 0.42) * 0.5 + 0.5);
    final pinchAmt = w * 0.07 * pinch * (0.4 + 0.6 * difficulty);
    return (base - pinchAmt).clamp(w * 0.13, w * 0.42);
  }

  double _innerHalf(double d) => tubeHalfWidth(d) - ballRadius - 3;

  double itemX(double d, double lane) =>
      tubeCenter(d) + lane * (_innerHalf(d)).clamp(0, screenWidth);

  double depthToScreenY(double d) =>
      ballScreenY + (d - depth) * pixelsPerMeter;

  double get fallSpeed {
    final difficulty = (depth / 2500).clamp(0.0, 1.0);
    double s = 13.5 + difficulty * 13.0; // meters/sec
    if (boostTimer > 0) s *= 1.45;
    return s;
  }

  // ── Lifecycle ──

  void startGame() {
    state = GameState.playing;
    depth = 0;
    score = 0;
    coinsCollected = 0;
    shieldsGrabbed = 0;
    multiplier = 1.0;
    heat = 0;
    ballX = screenWidth / 2;
    targetX = screenWidth / 2;
    ballVX = 0;
    shieldTimer = startShield;
    slowmoTimer = 0;
    boostTimer = 0;
    timeScale = 1.0;
    deathTimer = 0;
    shake = 0;
    spikes.clear();
    blades.clear();
    gates.clear();
    mines.clear();
    coins.clear();
    powerups.clear();
    particles.clear();
    _genCursor = 14;
    _generateAhead();
  }

  void returnToMenu() {
    state = GameState.menu;
    spikes.clear();
    blades.clear();
    gates.clear();
    mines.clear();
    coins.clear();
    powerups.clear();
    particles.clear();
    depth = 0;
    heat = 0;
    ballX = screenWidth / 2;
    targetX = screenWidth / 2;
  }

  void togglePause() {
    if (state == GameState.playing) {
      state = GameState.paused;
    } else if (state == GameState.paused) {
      state = GameState.playing;
    }
  }

  void setTarget(double x) {
    targetX = x.clamp(0, screenWidth);
  }

  // ── Generation ──

  double get _genAheadMeters => screenHeight / pixelsPerMeter + 22;

  void _generateAhead() {
    while (_genCursor < depth + _genAheadMeters) {
      _spawnFeature(_genCursor);
      final difficulty = (depth / 2200).clamp(0.0, 1.0);
      final gap = (10.0 - 4.5 * difficulty) + _rng.nextDouble() * 4.0;
      _genCursor += gap.clamp(4.5, 14.0);
    }
  }

  void _spawnFeature(double d) {
    final difficulty = (depth / 2200).clamp(0.0, 1.0);
    final roll = _rng.nextDouble();

    final powerChance = 0.10;
    final spikeChance = 0.19 + difficulty * 0.20;
    final bladeChance = 0.08 + difficulty * 0.17;
    final gateChance = 0.06 + difficulty * 0.15;
    final mineChance = 0.05 + difficulty * 0.13;

    if (roll < powerChance) {
      final types = PowerType.values;
      final t = types[_rng.nextInt(types.length)];
      powerups.add(PowerUp(d, (_rng.nextDouble() * 1.4 - 0.7), t));
      return;
    }

    var cursor = powerChance;
    if (roll < cursor + spikeChance) {
      // 1-2 spikes from sides, always leaving a center gap.
      final both = difficulty > 0.45 && _rng.nextDouble() < 0.4;
      final pulsing = difficulty > 0.3 && _rng.nextDouble() < 0.35;
      final protrude = 0.42 + _rng.nextDouble() * 0.12;
      if (both) {
        spikes.add(Spike(d, 0.9, true, protrude, pulsing: pulsing));
        spikes.add(Spike(d, 0.9, false, protrude, pulsing: pulsing));
      } else {
        spikes.add(Spike(d, 0.9, _rng.nextBool(),
            0.5 + _rng.nextDouble() * 0.18,
            pulsing: pulsing));
      }
      _maybeCoinArc(d + 3.5);
      return;
    }
    cursor += spikeChance;

    if (roll < cursor + bladeChance) {
      // Single blade, or a synchronized pair for harder patterns.
      final pair = difficulty > 0.5 && _rng.nextDouble() < 0.35;
      final lane = _rng.nextDouble() * 1.2 - 0.6;
      final drift =
          _rng.nextDouble() < 0.6 ? (0.3 + _rng.nextDouble() * 0.4) : 0.0;
      final freq = 0.6 + _rng.nextDouble() * 0.8;
      final phase = _rng.nextDouble() * pi * 2;
      blades.add(Blade(d, 1.0, lane, drift, freq, phase,
          ballRadius * (0.95 + _rng.nextDouble() * 0.5)));
      if (pair) {
        blades.add(Blade(d + 2.0, 1.0, -lane, drift, freq, phase + pi,
            ballRadius * (0.95 + _rng.nextDouble() * 0.4)));
      }
      return;
    }
    cursor += bladeChance;

    if (roll < cursor + gateChance) {
      // Bar across the tube with a single passable opening.
      final gapLane = _rng.nextDouble() * 1.2 - 0.6;
      final gapHalf = (0.46 - difficulty * 0.14) + _rng.nextDouble() * 0.06;
      final drift = difficulty > 0.55 && _rng.nextDouble() < 0.4
          ? 0.25 + _rng.nextDouble() * 0.3
          : 0.0;
      gates.add(Gate(d, 0.7, gapLane.clamp(-0.55, 0.55), gapHalf, drift,
          0.5 + _rng.nextDouble() * 0.6, _rng.nextDouble() * pi * 2));
      _maybeCoinArc(d - 5.0);
      return;
    }
    cursor += gateChance;

    if (roll < cursor + mineChance) {
      final n = 1 + (difficulty > 0.5 ? _rng.nextInt(2) : 0);
      for (int i = 0; i < n; i++) {
        mines.add(Mine(
          d + i * 3.0,
          0.8,
          _rng.nextDouble() * 1.4 - 0.7,
          0.2 + _rng.nextDouble() * 0.45,
          0.5 + _rng.nextDouble() * 0.9,
          _rng.nextDouble() * pi * 2,
          ballRadius * (0.85 + _rng.nextDouble() * 0.3),
        ));
      }
      return;
    }

    // Otherwise a coin pattern.
    _maybeCoinArc(d);
  }

  /// Current protrusion fraction of a spike (animated when pulsing).
  double spikeProtrude(Spike s) {
    if (!s.pulsing) return s.protrudeFrac;
    final p = 0.5 + 0.5 * sin(menuTime * 2.6 + s.depth * 0.6);
    return s.protrudeFrac * (0.25 + 0.75 * p);
  }

  double gateGapLane(Gate g) =>
      (g.gapLane + sin(menuTime * g.driftFreq + g.phase) * g.driftAmp)
          .clamp(-0.6, 0.6);

  double mineX(Mine m) {
    final lane = m.lane + sin(menuTime * m.driftFreq + m.phase) * m.driftAmp;
    return itemX(m.depth, lane.clamp(-0.85, 0.85));
  }

  void _maybeCoinArc(double d) {
    final n = 2 + _rng.nextInt(4);
    final baseLane = _rng.nextDouble() * 1.0 - 0.5;
    final step = (_rng.nextDouble() - 0.5) * 0.25;
    for (int i = 0; i < n; i++) {
      final lane = (baseLane + step * i).clamp(-0.85, 0.85);
      coins.add(Coin(d + i * 2.0, lane));
    }
  }

  // ── Update ──

  void update(double dtRaw) {
    menuTime += dtRaw;
    if (pickupFlash > 0) pickupFlash -= dtRaw;

    if (state == GameState.menu) {
      // gentle idle motion for the ball preview
      return;
    }

    if (state == GameState.gameOver) {
      deathTimer += dtRaw;
      shake *= 0.9;
      _updateParticles(dtRaw);
      return;
    }

    if (state != GameState.playing) return;

    // Slow-mo handling
    final targetScale = slowmoTimer > 0 ? 0.45 : 1.0;
    timeScale += (targetScale - timeScale) * min(1.0, dtRaw * 8);
    final dt = dtRaw * timeScale;

    if (shieldTimer > 0) shieldTimer -= dtRaw;
    if (slowmoTimer > 0) slowmoTimer -= dtRaw;
    if (boostTimer > 0) boostTimer -= dtRaw;

    // Descend
    depth += fallSpeed * dt;
    _generateAhead();
    _cull();

    // Score
    multiplier = boostTimer > 0 ? 2.0 : 1.0;
    score += (fallSpeed * dt * 6 * multiplier).round();

    // Ball horizontal physics
    final dx = targetX - ballX;
    ballVX += dx * 22 * dt;
    ballVX *= (1 - min(1.0, 12 * dt));
    ballX += ballVX * dt;

    // Constrain to tube walls + heat from scraping
    final center = tubeCenter(depth);
    final half = tubeHalfWidth(depth);
    final leftWall = center - half + ballRadius;
    final rightWall = center + half - ballRadius;

    bool scraping = false;
    if (ballX < leftWall) {
      final pen = leftWall - ballX;
      ballX = leftWall;
      ballVX = 0;
      scraping = true;
      _scrapeHeat(pen, dtRaw);
    } else if (ballX > rightWall) {
      final pen = ballX - rightWall;
      ballX = rightWall;
      ballVX = 0;
      scraping = true;
      _scrapeHeat(pen, dtRaw);
    }

    if (!scraping) {
      heat -= dtRaw * 0.55;
      if (heat < 0) heat = 0;
    }

    if (heat >= 1.0 && shieldTimer <= 0) {
      _die(overheat: true);
      return;
    }

    _updateBlades(dtRaw);
    _collect();
    if (_checkObstacles()) {
      _die(overheat: false);
      return;
    }

    _updateParticles(dtRaw);
  }

  void _scrapeHeat(double pen, double dt) {
    if (shieldTimer > 0) return;
    final intensity = (0.4 + pen / (ballRadius * 2)).clamp(0.4, 1.4);
    heat += dt * 0.85 * intensity * heatGainMult;
    if (heat > 1.0) heat = 1.0;
    shake = max(shake, 3.0);
    if (_rng.nextDouble() < 0.5) {
      _spawnSparks(ballX, ballScreenY, 2, const Color(0xFFFF7043));
    }
  }

  void _updateBlades(double dt) {
    for (final b in blades) {
      b.spin += dt * 9;
    }
    for (final m in mines) {
      m.spin += dt * 4;
    }
  }

  void _cull() {
    final behind = depth - 6;
    spikes.removeWhere((o) => o.depth < behind);
    blades.removeWhere((o) => o.depth < behind);
    gates.removeWhere((o) => o.depth < behind);
    mines.removeWhere((o) => o.depth < behind);
    coins.removeWhere((c) => c.depth < behind);
    powerups.removeWhere((p) => p.depth < behind);
  }

  void _collect() {
    const pad = 1.4;
    for (final c in coins) {
      if (c.collected) continue;
      // Magnet widens the depth window so coins are pulled in earlier.
      final depthWindow = 2.2 + magnetRange / 40.0;
      if ((c.depth - depth).abs() > depthWindow) continue;
      final cx = itemX(c.depth, c.lane);
      final reach = ballRadius + 10 + (magnetRange * 0.6);
      if ((cx - ballX).abs() < reach) {
        c.collected = true;
        coinsCollected++;
        score += (5 * multiplier).round();
        _spawnSparks(cx, depthToScreenY(c.depth), 5, const Color(0xFFFFD740));
      }
    }

    for (final p in powerups) {
      if (p.collected) continue;
      if ((p.depth - depth).abs() > 2.4 + pad) continue;
      final px = itemX(p.depth, p.lane);
      if ((px - ballX).abs() < ballRadius + 22) {
        p.collected = true;
        _applyPower(p.type);
        _spawnSparks(px, depthToScreenY(p.depth), 14, _powerColor(p.type));
      }
    }
  }

  Color _powerColor(PowerType t) {
    switch (t) {
      case PowerType.shield:
        return const Color(0xFF40C4FF);
      case PowerType.slowmo:
        return const Color(0xFFB388FF);
      case PowerType.boost:
        return const Color(0xFFFFEA00);
    }
  }

  void _applyPower(PowerType t) {
    lastPickup = t;
    pickupFlash = 1.0;
    switch (t) {
      case PowerType.shield:
        shieldTimer = shieldDuration;
        shieldsGrabbed++;
        heat = 0;
        break;
      case PowerType.slowmo:
        slowmoTimer = slowmoDuration;
        break;
      case PowerType.boost:
        boostTimer = 4.0;
        break;
    }
  }

  bool _checkObstacles() {
    if (shieldTimer > 0) return false;

    final center = tubeCenter(depth);
    final half = tubeHalfWidth(depth);

    for (final s in spikes) {
      if ((s.depth - depth).abs() > s.depthHalf) continue;
      final protrudeLen = half * spikeProtrude(s);
      if (s.rightSide) {
        final tip = (center + half) - protrudeLen;
        if (ballX + ballRadius > tip) return true;
      } else {
        final tip = (center - half) + protrudeLen;
        if (ballX - ballRadius < tip) return true;
      }
    }

    for (final b in blades) {
      if ((b.depth - depth).abs() > b.depthHalf) continue;
      final bx = _bladeX(b);
      if ((bx - ballX).abs() < ballRadius + b.radius * 0.8) return true;
    }

    for (final m in mines) {
      if ((m.depth - depth).abs() > m.depthHalf) continue;
      final mx = mineX(m);
      if ((mx - ballX).abs() < ballRadius + m.radius * 0.85) return true;
    }

    for (final g in gates) {
      if ((g.depth - depth).abs() > g.depthHalf) continue;
      final gapCenter = itemX(g.depth, gateGapLane(g));
      final gapHalfPx = (g.gapHalf * _innerHalf(g.depth));
      if ((ballX - gapCenter).abs() > gapHalfPx - ballRadius) return true;
    }
    return false;
  }

  double _bladeX(Blade b) {
    final lane = b.lane + sin(menuTime * b.driftFreq + b.phase) * b.driftAmp;
    return itemX(b.depth, lane.clamp(-0.85, 0.85));
  }

  void _die({required bool overheat}) {
    state = GameState.gameOver;
    deathTimer = 0;
    shake = 16;
    _spawnSparks(ballX, ballScreenY, 40,
        overheat ? const Color(0xFFFF5252) : const Color(0xFF00E5FF));
    if (score > highScore) highScore = score;
    if (distance > bestDistance) bestDistance = distance;
  }

  // ── Particles ──

  void _spawnSparks(double x, double y, int n, Color color) {
    for (int i = 0; i < n; i++) {
      final a = _rng.nextDouble() * pi * 2;
      final sp = 40 + _rng.nextDouble() * 220;
      particles.add(Particle(
        x,
        y,
        cos(a) * sp,
        sin(a) * sp,
        0.4 + _rng.nextDouble() * 0.5,
        2 + _rng.nextDouble() * 4,
        color,
      ));
    }
  }

  void _updateParticles(double dt) {
    for (final p in particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 240 * dt;
      p.vx *= (1 - min(1.0, 1.5 * dt));
      p.life -= dt;
    }
    particles.removeWhere((p) => p.life <= 0);
  }

  // ── For menu preview bobbing ──
  double get menuBob => sin(menuTime * 2.2) * 10;
}
