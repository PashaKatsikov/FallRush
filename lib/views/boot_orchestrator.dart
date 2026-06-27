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

class _BootOrchestratorState extends State<BootOrchestrator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _barCtrl;
  double _progress = 0;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addListener(() {
        if (mounted) setState(() => _progress = _barCtrl.value);
      });
    _barCtrl.forward();
    _kickOff();
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  Future<void> _kickOff() async {
    widget.beacons.onTokenRotated = _onTokenRotated;
    await widget.beacons.wakeUp().catchError((_) {});

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

    await widget.attribution.boot();
    await Future.wait([
      widget.attribution.awaitAttribution(timeoutSec: 30),
      widget.attribution.awaitDeepLink(timeoutSec: 5),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.assembleConfigBody(
      locale: locale,
      pushToken: widget.beacons.token,
    );
    final verdict = await widget.gateway.askBackend(body);

    if (verdict.hasTarget) {
      await widget.vault.commitPath(LaunchPath.stream);
      await _finishProgress();
      if (!mounted) return;
      _gotoStream(verdict.target!);
    } else {
      await widget.vault.commitPath(LaunchPath.arcade);
      await GameAssets().loadAll();
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

    // Cold-tap push URL takes precedence over the saved one.
    final pendingPush = await widget.vault.takePushUrl();
    if (pendingPush != null) {
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

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.assembleConfigBody(
      locale: locale,
      pushToken: widget.beacons.token,
    );
    final verdict = await widget.gateway.askBackend(body);

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
    await GameAssets().loadAll();
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

  Future<void> _finishProgress() async {
    if (_barCtrl.value < 1.0) {
      _barCtrl.duration = const Duration(milliseconds: 300);
      await _barCtrl.forward(from: _barCtrl.value);
    }
    await Future.delayed(const Duration(milliseconds: 240));
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 10,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.14),
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF00E5FF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'LOADING ${(_progress * 100).round()}%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
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
