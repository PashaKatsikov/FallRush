import 'dart:io';

import 'package:flutter/material.dart';
import '../game/game_assets.dart';
import '../game/game_screen.dart';
import '../network/attribution_tracker.dart';
import '../network/beacon_center.dart';
import '../network/config_gateway.dart';
import '../network/network_probe.dart';
import '../network/session_vault.dart';
import '../types/launch_path.dart';
import 'alert_optin_page.dart';
import 'offline_lapse_page.dart';
import 'web_shell_page.dart' deferred as shell;

/// First widget shown after `runApp()`. Drives the gray-flow state
/// machine, plays an animated progress while we wait on the
/// network, and finally routes to either the WebView shell or the
/// in-app arcade.
class BootOrchestrator extends StatefulWidget {
  final SessionVault vault;
  final NetworkProbe probe;
  final AttributionTracker attribution;
  final ConfigGateway gateway;
  final BeaconCenter beacons;

  const BootOrchestrator({
    super.key,
    required this.vault,
    required this.probe,
    required this.attribution,
    required this.gateway,
    required this.beacons,
  });

  @override
  State<BootOrchestrator> createState() => _BootOrchestratorState();
}

class _BootOrchestratorState extends State<BootOrchestrator> {
  /// Видимое значение полосы (то, что рисуется). Плавно догоняет
  /// `_target` через `_animateBar`.
  double _progress = 0;

  /// Куда нужно «доехать» бару. Обновляется по реальным вехам:
  /// 0.10 — booted, online, vault готов
  /// 0.30 — beacons.wakeUp() закончен (Firebase, FCM token)
  /// 0.55 — attribution + deep link готовы
  /// 0.85 — backend verdict получен
  /// 0.95 — assets / web shell прелоудены
  /// 1.00 — мы прямо сейчас уходим со splash на следующий экран
  double _target = 0;
  bool _routed = false;

  /// «Watchdog»: даже если все шаги отработают мгновенно, держим бар
  /// видимым минимум 700 мс, чтобы переход не выглядел дёрганым.
  late final DateTime _bornAt;
  static const Duration _minSplashTime = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    _bornAt = DateTime.now();
    _kickOff();
  }

  // ── progress engine ────────────────────────────────────────────────
  //
  // Полоса больше НЕ привязана к фиксированному таймеру. Раньше
  // `AnimationController(duration: 2200ms)` доезжал до 100% за 2.2 с
  // независимо от реальной готовности: при медленной сети бар
  // упирался в правый край и стоял, при быстрой — игра успевала
  // открыться раньше, чем бар догонял.
  //
  // Теперь _setTarget(x) задаёт целевое значение, _animateBar()
  // плавно докатывает _progress до _target. На каждой реальной вехе
  // (online, beacons, attribution, verdict, prime) мы зовём
  // _setTarget(...) и ждём окончания анимации. 100% появляется
  // ровно перед навигацией на следующий экран.

  Future<void> _setTarget(double next, {int millis = 350}) async {
    _target = next.clamp(0.0, 1.0);
    if (!mounted) return;
    final from = _progress;
    final to = _target;
    if ((to - from).abs() < 0.001) return;
    final steps = (millis / 16).round().clamp(1, 200);
    for (var i = 1; i <= steps; i++) {
      if (!mounted) return;
      final t = i / steps;
      final eased = Curves.easeOutCubic.transform(t);
      setState(() => _progress = from + (to - from) * eased);
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (!mounted) return;
    setState(() => _progress = to);
  }

  Future<void> _kickOff() async {
    widget.beacons.onTokenRotated = _onTokenRotated;
    // 10% — первый кадр нарисован, vault уже warmUp'нут до runApp.
    await _setTarget(0.10, millis: 250);

    await widget.beacons.wakeUp().catchError((_) {});
    // 30% — Firebase + FCM token готовы (или Firebase упал и мы
    // продолжаем без пуша — без разницы для прогресса).
    await _setTarget(0.30, millis: 350);

    switch (widget.vault.currentPath()) {
      case LaunchPath.stream:
        await _routeReturningStream();
        break;
      case LaunchPath.arcade:
        await _routeArcade();
        break;
      case LaunchPath.pending:
        await _routeFirstLaunch();
        break;
    }
  }

  // ── First launch ─────────────────────────────────────────────

  Future<void> _routeFirstLaunch() async {
    if (!await widget.probe.isOnline()) {
      if (!mounted) return;
      _gotoOffline();
      return;
    }
    await _setTarget(0.40, millis: 200);

    await widget.attribution.boot();
    await Future.wait([
      widget.attribution.awaitAttribution(timeoutSec: 30),
      widget.attribution.awaitDeepLink(timeoutSec: 5),
    ]);
    await _setTarget(0.55, millis: 350);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.assembleConfigBody(
      locale: locale,
      pushToken: widget.beacons.token,
    );
    final verdict = await widget.gateway.askBackend(body);
    await _setTarget(0.85, millis: 350);

    if (verdict.hasTarget) {
      await widget.vault.commitPath(LaunchPath.stream);
      await _setTarget(0.95, millis: 200);
      await _finishProgress();
      if (!mounted) return;
      _gotoStream(verdict.target!);
    } else {
      await widget.vault.commitPath(LaunchPath.arcade);
      await GameAssets().loadAll();
      await _setTarget(0.95, millis: 250);
      await _finishProgress();
      if (!mounted) return;
      _gotoArcade();
    }
  }

  // ── Returning stream user ───────────────────────────────────

  Future<void> _routeReturningStream() async {
    if (!await widget.probe.isOnline()) {
      await _finishProgress();
      if (!mounted) return;
      _gotoOffline();
      return;
    }
    await _setTarget(0.40, millis: 200);

    // Cold-tap push URL takes precedence over the saved one.
    final pendingPush = await widget.vault.takePushUrl();
    if (pendingPush != null) {
      await _setTarget(0.95, millis: 200);
      await _finishProgress();
      if (!mounted) return;
      _gotoStream(pendingPush);
      return;
    }

    final savedUrl = await widget.vault.readStreamUrl();

    await widget.attribution.boot();
    await Future.wait([
      widget.attribution.awaitAttribution(timeoutSec: 10),
      widget.attribution.awaitDeepLink(timeoutSec: 5),
    ]);
    await _setTarget(0.55, millis: 350);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.assembleConfigBody(
      locale: locale,
      pushToken: widget.beacons.token,
    );
    final verdict = await widget.gateway.askBackend(body);
    await _setTarget(0.90, millis: 350);

    await _finishProgress();
    if (!mounted) return;

    if (verdict.hasTarget) {
      _gotoStream(verdict.target!);
    } else if (savedUrl != null && savedUrl.isNotEmpty) {
      _gotoStream(savedUrl);
    } else {
      _gotoOffline();
    }
  }

  // ── Returning arcade user ───────────────────────────────────

  Future<void> _routeArcade() async {
    await _setTarget(0.50, millis: 200);
    await GameAssets().loadAll();
    await _setTarget(0.95, millis: 250);
    await _finishProgress();
    if (!mounted) return;
    _gotoArcade();
  }

  // ── Token refresh hook ──────────────────────────────────────

  Future<void> _onTokenRotated(String token) async {
    try {
      final locale = Platform.localeName.replaceAll('-', '_');
      final body = await widget.attribution.assembleConfigBody(
        locale: locale,
        pushToken: token,
      );
      await widget.gateway.askBackend(body);
    } catch (_) {}
  }

  // ── Navigators ──────────────────────────────────────────────

  Future<void> _gotoStream(String url) async {
    if (_routed) return;
    _routed = true;

    await shell.loadLibrary();
    await shell.primeWebShell();
    if (!mounted) return;

    if (widget.vault.shouldShowPushPromo()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AlertOptInPage(
            vault: widget.vault,
            beacons: widget.beacons,
            probe: widget.probe,
            contentUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => shell.WebShellPage(
            startUrl: url,
            vault: widget.vault,
            beacons: widget.beacons,
            probe: widget.probe,
          ),
        ),
      );
    }
  }

  void _gotoOffline() {
    if (_routed) return;
    _routed = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineLapsePage(
          revival: (_) => BootOrchestrator(
            vault: widget.vault,
            probe: widget.probe,
            attribution: widget.attribution,
            gateway: widget.gateway,
            beacons: widget.beacons,
          ),
        ),
      ),
    );
  }

  void _gotoArcade() {
    if (_routed) return;
    _routed = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, anim, _) => const GameScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  /// Финал: добиваем полосу до 100% и держим её на экране минимум
  /// `_minSplashTime`, чтобы splash не «моргнул» за 50 мс на быстрой
  /// сети. Только после этого вызывающий код делает Navigator.push.
  Future<void> _finishProgress() async {
    await _setTarget(1.0, millis: 250);
    final elapsed = DateTime.now().difference(_bornAt);
    final remaining = _minSplashTime - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
  }

  // ── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05060F),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final asset = orientation == Orientation.landscape
              ? 'assets/assets_webp/Horizontal_Loading_Screen.webp'
              : 'assets/assets_webp/Vertical_Loading_Screen.webp';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                asset,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF05060F)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 40,
                child: Center(
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width *
                        (orientation == Orientation.landscape ? 0.4 : 0.62),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF05060F).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.9),
                              width: 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.55),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.55),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: LinearProgressIndicator(
                              value: _progress,
                              minHeight: 12,
                              backgroundColor: Colors.black.withValues(alpha: 0.6),
                              valueColor: const AlwaysStoppedAnimation(
                                Color(0xFF00E5FF),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'LOADING ${(_progress * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                            shadows: [
                              Shadow(
                                color: Color(0xCC000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                              Shadow(
                                color: Color(0x8800E5FF),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
