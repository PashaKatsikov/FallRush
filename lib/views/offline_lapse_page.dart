import 'package:flutter/material.dart';

/// Screen shown when the device has no internet. Uses a static
/// background illustration (different per orientation) plus a
/// neon "Reconnect" pill. Tapping retry rebuilds the supplied
/// `revival` widget — typically the boot orchestrator.
class OfflineLapsePage extends StatefulWidget {
  final WidgetBuilder revival;

  const OfflineLapsePage({super.key, required this.revival});

  @override
  State<OfflineLapsePage> createState() => _OfflineLapsePageState();
}

class _OfflineLapsePageState extends State<OfflineLapsePage>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _reconnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.revival),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final asset = orientation == Orientation.landscape
        ? 'assets/assets_webp/nowifi_horizontal.webp'
        : 'assets/assets_webp/nowifi_vertical.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF05060F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF05060F)),
          ),
          // Slight bottom shadow so the button sits cleanly over busy art.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom +
                (orientation == Orientation.landscape ? 28 : 64),
            child: Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width *
                    (orientation == Orientation.landscape ? 0.38 : 0.72),
                child: _NeonPillButton(
                  label: _busy ? 'Reconnecting…' : 'Reconnect',
                  showSpinner: _busy,
                  pulse: _pulse,
                  onTap: _reconnect,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeonPillButton extends StatefulWidget {
  final String label;
  final bool showSpinner;
  final AnimationController pulse;
  final VoidCallback onTap;

  const _NeonPillButton({
    required this.label,
    required this.showSpinner,
    required this.pulse,
    required this.onTap,
  });

  @override
  State<_NeonPillButton> createState() => _NeonPillButtonState();
}

class _NeonPillButtonState extends State<_NeonPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.pulse,
      builder: (_, _) {
        final glow = 0.45 + widget.pulse.value * 0.45;
        return GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 90),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E20),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.9),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: glow),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: const Color(0xFFFF00C8).withValues(alpha: glow * 0.55),
                    blurRadius: 36,
                    spreadRadius: -2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.showSpinner) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      widget.label.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
