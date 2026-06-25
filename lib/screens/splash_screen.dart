import 'package:flutter/material.dart';
import '../game/game_assets.dart';
import '../game/game_screen.dart';

/// Loading screen. Works in BOTH orientations (the only screen that does):
/// it swaps between the vertical and horizontal artwork based on the current
/// device orientation. Once assets are ready it routes to the game, which
/// locks itself to portrait.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0;
  bool _navigated = false;
  late final AnimationController _barController;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..addListener(() {
        setState(() => _progress = _barController.value);
      });
    _run();
  }

  Future<void> _run() async {
    _barController.forward();
    final started = DateTime.now();

    await GameAssets().loadAll();

    // Keep the splash visible for a minimum, pleasant duration.
    final elapsed = DateTime.now().difference(started);
    const minShow = Duration(milliseconds: 1700);
    if (elapsed < minShow) {
      await Future.delayed(minShow - elapsed);
    }
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondary) => const GameScreen(),
        transitionsBuilder: (context, anim, secondary, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _barController.dispose();
    super.dispose();
  }

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
                errorBuilder: (context, error, stack) =>
                    const ColoredBox(color: Color(0xFF05060F)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 40,
                child: Center(
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width *
                        (orientation == Orientation.landscape ? 0.4 : 0.6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 10,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.15),
                            valueColor: const AlwaysStoppedAnimation(
                                Color(0xFF00E5FF)),
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
