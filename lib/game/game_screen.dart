import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/progression.dart';
import '../services/storage_service.dart';
import 'game_assets.dart';
import 'game_engine.dart';
import 'game_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  final GameEngine _engine = GameEngine();
  final GameAssets _assets = GameAssets();
  final StorageService _storage = StorageService();

  late Ticker _ticker;
  Duration _lastTick = Duration.zero;

  bool _settled = false;
  List<int> _pendingLevelUps = [];
  int _runCoinReward = 0;
  int _runXp = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _engine.highScore = _storage.highScore;
    _engine.bestDistance = _storage.bestDistance;
    _applyUpgrades();
    _ticker = createTicker(_onTick)..start();
  }

  void _applyUpgrades() {
    _engine.applyUpgrades(
      heatShieldLvl: _storage.upgradeLevel(UpgradeId.heatShield),
      shieldDurationLvl: _storage.upgradeLevel(UpgradeId.shieldDuration),
      magnetLvl: _storage.upgradeLevel(UpgradeId.magnet),
      coinValueLvl: _storage.upgradeLevel(UpgradeId.coinValue),
      slowmoLvl: _storage.upgradeLevel(UpgradeId.slowmoDuration),
      startShieldLvl: _storage.upgradeLevel(UpgradeId.startShield),
    );
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.016
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    _engine.update(dt.clamp(0.0, 0.05));

    if (_engine.state == GameState.gameOver && !_settled) {
      _settleRun();
    }
    if (_engine.state == GameState.playing) {
      _settled = false;
    }
    setState(() {});
  }

  void _settleRun() {
    _settled = true;
    _runCoinReward = _engine.coinReward;
    _runXp = _engine.distance + _engine.coinsCollected * 3;

    _storage.addCoins(_runCoinReward);
    _pendingLevelUps = _storage.addXp(_runXp);
    _storage.recordRun(
      distance: _engine.distance,
      coins: _engine.coinsCollected,
      shields: _engine.shieldsGrabbed,
    );
    if (_engine.score > _storage.highScore) {
      _storage.highScore = _engine.score;
    }
    if (_engine.distance > _storage.bestDistance) {
      _storage.bestDistance = _engine.distance;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  SkinInfo get _skin => skinById(_storage.activeSkin);

  void _startGame() {
    _applyUpgrades();
    _pendingLevelUps = [];
    _engine.startGame();
    setState(() {});
  }

  // ── Input ──

  void _onPointer(Offset local) {
    if (_engine.state == GameState.playing) {
      _engine.setTarget(local.dx);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05060F),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _engine.setSize(constraints.maxWidth, constraints.maxHeight);
          return Listener(
            onPointerDown: (e) => _onPointer(e.localPosition),
            onPointerMove: (e) => _onPointer(e.localPosition),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: GamePainter(
                      engine: _engine,
                      assets: _assets,
                      skin: _skin,
                      time: _engine.menuTime,
                    ),
                  ),
                ),
                if (_engine.state == GameState.menu) _buildMenu(constraints),
                if (_engine.state == GameState.playing) _buildHud(),
                if (_engine.state == GameState.paused) _buildPause(),
                if (_engine.state == GameState.gameOver) _buildGameOver(),
              ],
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════ MENU ════════════════════════

  Widget _buildMenu(BoxConstraints c) {
    final level = _storage.level;
    final xp = _storage.xp;
    final curBase = xpForLevel(level);
    final nextBase = xpForLevel(level + 1);
    final progress =
        ((xp - curBase) / (nextBase - curBase)).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        _menuBackground(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _buildTopBar(level, progress),
                const Spacer(flex: 2),
                _buildTitle(),
                const SizedBox(height: 10),
                _ballPreview(),
                const Spacer(flex: 2),
                _neonButton(
                  label: 'PLAY',
                  icon: Icons.play_arrow_rounded,
                  colors: const [Color(0xFF00E5FF), Color(0xFF2979FF)],
                  big: true,
                  onTap: _startGame,
                ),
                const SizedBox(height: 16),
                if (_engine.bestDistance > 0 || _engine.highScore > 0)
                  _bestBadge(),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _menuChip(Icons.upgrade, 'UPGRADES',
                        () => _openHub(0), const Color(0xFF69F0AE)),
                    const SizedBox(width: 12),
                    _menuChip(Icons.palette, 'SKINS', () => _openHub(1),
                        const Color(0xFFFF80AB)),
                    const SizedBox(width: 12),
                    _menuChip(Icons.flag, 'MISSIONS', () => _openHub(2),
                        const Color(0xFFFFD740)),
                  ],
                ),
                const Spacer(flex: 1),
                _dailyWidget(),
                const SizedBox(height: 12),
                Text('Drag to steer the ball · avoid walls, blades & gates',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12)),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Bright, branded menu backdrop so the menu isn't just the dark game canvas.
  Widget _menuBackground() {
    final t = _engine.menuTime;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF161B45),
                Color(0xFF241148),
                Color(0xFF0A0B1E),
              ],
            ),
          ),
        ),
        Opacity(
          opacity: 0.35,
          child: Image.asset('assets/assets_webp/bg_1_asset.webp',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) =>
                  const SizedBox.shrink()),
        ),
        // animated soft glow blobs
        Positioned(
          top: 80 + sin(t * 0.8) * 20,
          left: -60,
          child: _glowBlob(const Color(0xFF00E5FF), 220),
        ),
        Positioned(
          bottom: 120 + cos(t * 0.6) * 24,
          right: -50,
          child: _glowBlob(const Color(0xFFFF00C8), 240),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 1.1,
              colors: [Colors.transparent, Color(0xCC0A0B1E)],
              stops: [0.55, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _glowBlob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.5), Colors.transparent],
        ),
      ),
    );
  }

  Widget _ballPreview() {
    final skin = _skin;
    final bob = sin(_engine.menuTime * 2.2) * 8;
    final glowPulse = 0.5 + 0.5 * sin(_engine.menuTime * 3);
    final tint = skin.id == 'rainbow'
        ? HSVColor.fromAHSV(1, (_engine.menuTime * 90) % 360, 0.85, 1).toColor()
        : skin.tint;
    Widget ball = Image.asset('assets/assets_webp/ball_asset.webp',
        width: 110, height: 110, fit: BoxFit.contain);
    final strength = skin.id == 'rainbow' ? 0.5 : skin.tintStrength;
    if (strength > 0) {
      ball = ColorFiltered(
        colorFilter: ColorFilter.mode(
            tint.withValues(alpha: strength), BlendMode.srcATop),
        child: ball,
      );
    }
    return Transform.translate(
      offset: Offset(0, bob),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: tint.withValues(alpha: 0.3 + glowPulse * 0.35),
                blurRadius: 30 + glowPulse * 20,
                spreadRadius: 4),
          ],
        ),
        child: ball,
      ),
    );
  }

  Widget _dailyWidget() {
    if (_storage.canClaimDaily) return _dailyButton();
    // Already claimed today — show a clear "claimed" state.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, color: Color(0xFF69F0AE), size: 18),
        const SizedBox(width: 8),
        Text('DAILY BONUS CLAIMED',
            style: TextStyle(
                color: const Color(0xFF69F0AE).withValues(alpha: 0.9),
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1)),
        const SizedBox(width: 8),
        Text('· back tomorrow',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
      ]),
    );
  }

  Widget _buildTopBar(int level, double progress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF2979FF)]),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                    blurRadius: 12)
              ],
            ),
            alignment: Alignment.center,
            child: Text('$level',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LEVEL $level',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _coinPill(),
        ],
      ),
    );
  }

  Widget _coinPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.monetization_on, color: Colors.amber, size: 18),
        const SizedBox(width: 5),
        Text('${_storage.coins}',
            style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ]),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0xFF00E5FF), Color(0xFFB388FF), Color(0xFFFF00C8)],
          ).createShader(r),
          child: const Text('FALL',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 62,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                  letterSpacing: 4)),
        ),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0xFFFF00C8), Color(0xFFB388FF), Color(0xFF00E5FF)],
          ).createShader(r),
          child: const Text('RUSH',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 62,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                  letterSpacing: 4)),
        ),
      ],
    );
  }

  Widget _bestBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.emoji_events, color: Color(0xFFFFD740), size: 18),
        const SizedBox(width: 6),
        Text('BEST  ${_engine.bestDistance}m',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(width: 14),
        const Icon(Icons.star, color: Color(0xFF00E5FF), size: 18),
        const SizedBox(width: 6),
        Text('${_engine.highScore}',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      ]),
    );
  }

  Widget _menuChip(
      IconData icon, String label, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  Widget _dailyButton() {
    return GestureDetector(
      onTap: _claimDaily,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFFD740), Color(0xFFFF9800)]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.amber.withValues(alpha: 0.5), blurRadius: 14)
          ],
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.card_giftcard, color: Colors.black, size: 20),
          SizedBox(width: 8),
          Text('CLAIM DAILY BONUS',
              style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1)),
        ]),
      ),
    );
  }

  void _claimDaily() {
    final reward = 100 + _storage.level * 15;
    _storage.addCoins(reward);
    _storage.lastDailyClaim = DateTime.now().millisecondsSinceEpoch;
    setState(() {});
    _toast('Daily bonus: +$reward coins!');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFF1A1F3A),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ════════════════════════ HUD ════════════════════════

  Widget _buildHud() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hudPill(Icons.south, '${_engine.distance}m',
                        const Color(0xFF00E5FF)),
                    const SizedBox(height: 6),
                    _hudPill(Icons.star, '${_engine.score}',
                        Colors.white),
                    const SizedBox(height: 6),
                    _hudPill(Icons.monetization_on,
                        '${_engine.coinsCollected}', Colors.amber),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_engine.multiplier > 1)
                      _hudPill(Icons.bolt, 'x2', const Color(0xFFFFEA00)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => setState(() => _engine.togglePause()),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: const Icon(Icons.pause,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _heatBar(),
            const Spacer(),
            _activePowerBadges(),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _heatBar() {
    final heat = _engine.heat;
    return Row(
      children: [
        const Icon(Icons.local_fire_department,
            color: Color(0xFFFF7043), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: heat,
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(
                Color.lerp(const Color(0xFFFFB300), const Color(0xFFFF1744),
                    heat)!,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _activePowerBadges() {
    final badges = <Widget>[];
    if (_engine.shieldTimer > 0) {
      badges.add(_powerBadge(Icons.shield, _engine.shieldTimer,
          const Color(0xFF40C4FF)));
    }
    if (_engine.slowmoTimer > 0) {
      badges.add(_powerBadge(Icons.hourglass_bottom, _engine.slowmoTimer,
          const Color(0xFFB388FF)));
    }
    if (_engine.boostTimer > 0) {
      badges.add(_powerBadge(
          Icons.bolt, _engine.boostTimer, const Color(0xFFFFEA00)));
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: badges,
    );
  }

  Widget _powerBadge(IconData icon, double t, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 5),
        Text('${t.toStringAsFixed(1)}s',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ]),
    );
  }

  Widget _hudPill(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 5),
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 15)),
      ]),
    );
  }

  // ════════════════════════ PAUSE ════════════════════════

  Widget _buildPause() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.pause_circle_outline,
                color: Colors.white, size: 76),
            const SizedBox(height: 12),
            const Text('PAUSED',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4)),
            const SizedBox(height: 28),
            _neonButton(
              label: 'RESUME',
              icon: Icons.play_arrow_rounded,
              colors: const [Color(0xFF00E5FF), Color(0xFF2979FF)],
              onTap: () => setState(() => _engine.togglePause()),
            ),
            const SizedBox(height: 14),
            _ghostButton('QUIT TO MENU', Icons.home,
                () => setState(() => _engine.returnToMenu())),
          ]),
        ),
      ),
    );
  }

  // ════════════════════════ GAME OVER ════════════════════════

  Widget _buildGameOver() {
    final show = _engine.deathTimer > 0.8;
    final newBest = _engine.distance >= _storage.bestDistance &&
        _engine.distance > 0;
    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      child: IgnorePointer(
        ignoring: !show,
        child: Container(
          color: Colors.black.withValues(alpha: 0.82),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('RUN OVER',
                      style: TextStyle(
                          color: Color(0xFFFF1744),
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4)),
                  const SizedBox(height: 4),
                  if (newBest)
                    Container(
                      margin: const EdgeInsets.only(top: 6, bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFFFFD740),
                          Color(0xFFFF9800)
                        ]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text('NEW RECORD!',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 1)),
                    ),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                        child: _statCard(Icons.south, 'DISTANCE',
                            '${_engine.distance}m', const Color(0xFF00E5FF))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _statCard(Icons.star, 'SCORE',
                            '${_engine.score}', Colors.white)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: _statCard(
                            Icons.monetization_on,
                            'COINS +',
                            '$_runCoinReward',
                            Colors.amber)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _statCard(Icons.auto_awesome, 'XP +',
                            '$_runXp', const Color(0xFFB388FF))),
                  ]),
                  if (_pendingLevelUps.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFF00E5FF),
                          Color(0xFFB388FF)
                        ]),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                          'LEVEL UP!  ${_pendingLevelUps.first} → ${_pendingLevelUps.last}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 1)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _neonButton(
                    label: 'RETRY',
                    icon: Icons.replay,
                    colors: const [Color(0xFF69F0AE), Color(0xFF00BFA5)],
                    big: true,
                    onTap: _startGame,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ghostButton('UPGRADES', Icons.upgrade,
                          () => _openHub(0)),
                      const SizedBox(width: 12),
                      _ghostButton('MENU', Icons.home,
                          () => setState(() => _engine.returnToMenu())),
                    ],
                  ),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  // ════════════════════════ SHARED BUTTONS ════════════════════════

  Widget _neonButton({
    required String label,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
    bool big = false,
  }) {
    final pulse = (sin(_engine.menuTime * 3) + 1) / 2;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: big ? 52 : 28, vertical: big ? 18 : 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
                color: colors[0].withValues(alpha: 0.4 + pulse * 0.3),
                blurRadius: 18 + pulse * 10,
                offset: const Offset(0, 5)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: big ? 28 : 22),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: big ? 24 : 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3)),
        ]),
      ),
    );
  }

  Widget _ghostButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1)),
        ]),
      ),
    );
  }

  // ════════════════════════ HUB (shop/skins/missions) ════════════════════════

  void _openHub(int initialTab) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HubSheet(
        storage: _storage,
        assets: _assets,
        initialTab: initialTab,
        onChanged: () {
          _applyUpgrades();
          setState(() {});
        },
      ),
    ).then((_) => setState(() {}));
  }
}

// ════════════════════════════════════════════════════════════
// HUB BOTTOM SHEET — Upgrades / Skins / Missions
// ════════════════════════════════════════════════════════════

class _HubSheet extends StatefulWidget {
  final StorageService storage;
  final GameAssets assets;
  final int initialTab;
  final VoidCallback onChanged;

  const _HubSheet({
    required this.storage,
    required this.assets,
    required this.initialTab,
    required this.onChanged,
  });

  @override
  State<_HubSheet> createState() => _HubSheetState();
}

class _HubSheetState extends State<_HubSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: 3, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  StorageService get s => widget.storage;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0C1024),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
                top: BorderSide(color: Color(0xFF1E2547), width: 1)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Text('SHOP',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.monetization_on,
                            color: Colors.amber, size: 18),
                        const SizedBox(width: 5),
                        Text('${s.coins}',
                            style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TabBar(
                controller: _tab,
                indicatorColor: const Color(0xFF00E5FF),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: 'UPGRADES'),
                  Tab(text: 'SKINS'),
                  Tab(text: 'MISSIONS'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _upgradesTab(scrollController),
                    _skinsTab(scrollController),
                    _missionsTab(scrollController),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Upgrades ──

  Widget _upgradesTab(ScrollController sc) {
    return ListView.builder(
      controller: sc,
      padding: const EdgeInsets.all(16),
      itemCount: allUpgrades.length,
      itemBuilder: (_, i) {
        final u = allUpgrades[i];
        final lvl = s.upgradeLevel(u.id);
        final cost = u.costForLevel(lvl);
        final maxed = cost < 0;
        final canBuy = !maxed && s.coins >= cost;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: u.color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: u.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(u.icon, color: u.color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(u.description,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11)),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(u.maxLevel, (j) {
                      return Container(
                        width: 18,
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: j < lvl
                              ? u.color
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: maxed || !canBuy
                  ? null
                  : () {
                      s.spendCoins(cost);
                      s.setUpgradeLevel(u.id, lvl + 1);
                      widget.onChanged();
                      setState(() {});
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: canBuy
                      ? LinearGradient(
                          colors: [u.color, u.color.withValues(alpha: 0.7)])
                      : null,
                  color: canBuy
                      ? null
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: maxed
                    ? const Text('MAX',
                        style: TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 13))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.monetization_on,
                            color: canBuy ? Colors.black : Colors.white38,
                            size: 15),
                        const SizedBox(width: 4),
                        Text('$cost',
                            style: TextStyle(
                                color:
                                    canBuy ? Colors.black : Colors.white38,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ]),
              ),
            ),
          ]),
        );
      },
    );
  }

  // ── Skins ──

  Widget _skinsTab(ScrollController sc) {
    return GridView.builder(
      controller: sc,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.92,
      ),
      itemCount: allSkins.length,
      itemBuilder: (_, i) {
        final skin = allSkins[i];
        final owned = s.ownedSkins.contains(skin.id);
        final active = s.activeSkin == skin.id;
        final levelLocked =
            skin.unlockLevel > 0 && s.level < skin.unlockLevel;
        final canBuy = !owned && !levelLocked && s.coins >= skin.price;

        return GestureDetector(
          onTap: () {
            if (active) return;
            if (owned) {
              s.activeSkin = skin.id;
            } else if (levelLocked) {
              return;
            } else if (canBuy) {
              s.spendCoins(skin.price);
              s.addOwnedSkin(skin.id);
              s.activeSkin = skin.id;
            } else {
              return;
            }
            widget.onChanged();
            setState(() {});
          },
          child: Container(
            decoration: BoxDecoration(
              color: active
                  ? skin.tint.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active
                    ? skin.tint.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.08),
                width: active ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                _skinPreview(skin),
                const SizedBox(height: 8),
                Text(skin.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 6),
                _skinStatus(skin, owned, active, levelLocked, canBuy),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _skinPreview(SkinInfo skin) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: skin.tint.withValues(alpha: 0.5), blurRadius: 16)
        ],
      ),
      child: ColorFiltered(
        colorFilter: skin.tintStrength > 0
            ? ColorFilter.mode(
                skin.tint.withValues(alpha: skin.tintStrength),
                BlendMode.srcATop)
            : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
        child: Image.asset('assets/assets_webp/ball_asset.webp',
            fit: BoxFit.contain),
      ),
    );
  }

  Widget _skinStatus(SkinInfo skin, bool owned, bool active,
      bool levelLocked, bool canBuy) {
    if (active) {
      return _tag('EQUIPPED', const Color(0xFF00E5FF));
    }
    if (owned) {
      return _tag('EQUIP', const Color(0xFF69F0AE));
    }
    if (levelLocked) {
      return _tag('LVL ${skin.unlockLevel}', Colors.white38);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: canBuy
            ? const LinearGradient(
                colors: [Color(0xFFFFD740), Color(0xFFFF9800)])
            : null,
        color: canBuy ? null : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.monetization_on,
            color: canBuy ? Colors.black : Colors.white38, size: 14),
        const SizedBox(width: 4),
        Text('${skin.price}',
            style: TextStyle(
                color: canBuy ? Colors.black : Colors.white38,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ]),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  // ── Missions ──

  Widget _missionsTab(ScrollController sc) {
    return ListView.builder(
      controller: sc,
      padding: const EdgeInsets.all(16),
      itemCount: missionTiers.length,
      itemBuilder: (_, i) {
        final m = missionTiers[i];
        final tierIdx = s.missionTierIndex(m.metric);
        final completed = tierIdx >= m.targets.length;
        final target = completed ? m.targets.last : m.targets[tierIdx];
        final reward = completed ? 0 : m.rewards[tierIdx];
        final progress = s.statForMetric(m.metric);
        final claimable = !completed && progress >= target;
        final pct = (progress / target).clamp(0.0, 1.0);
        final label = m.label.replaceAll('%d', '$target');

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: claimable
                    ? const Color(0xFFFFD740).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(m.icon, color: const Color(0xFFFFD740), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(completed ? 'ALL TIERS COMPLETE' : label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                if (!completed)
                  Text('Tier ${tierIdx + 1}/${m.targets.length}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: completed ? 1.0 : pct,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(
                      claimable || completed
                          ? const Color(0xFFFFD740)
                          : const Color(0xFF00E5FF)),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Text(completed ? 'Done' : '$progress / $target',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12)),
                const Spacer(),
                if (claimable)
                  GestureDetector(
                    onTap: () {
                      s.addCoins(reward);
                      s.setMissionTierIndex(m.metric, tierIdx + 1);
                      widget.onChanged();
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFFFFD740),
                          Color(0xFFFF9800)
                        ]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.monetization_on,
                            color: Colors.black, size: 15),
                        const SizedBox(width: 4),
                        Text('CLAIM $reward',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 13)),
                      ]),
                    ),
                  )
                else if (!completed)
                  Text('+$reward',
                      style: const TextStyle(
                          color: Color(0xFFFFD740),
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
              ]),
            ],
          ),
        );
      },
    );
  }
}
