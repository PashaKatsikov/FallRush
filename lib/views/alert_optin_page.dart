import 'package:flutter/material.dart';
import '../network/beacon_center.dart';
import '../network/network_probe.dart';
import '../network/session_vault.dart';
import '../setup/runtime_profile.dart';
import 'web_shell_page.dart' deferred as shell;

/// Push opt-in promo. Shown once before the WebView opens.
/// Both buttons (Accept / Skip) update the session vault; the user
/// then lands on the WebView regardless of the answer.
class AlertOptInPage extends StatefulWidget {
  final SessionVault vault;
  final BeaconCenter beacons;
  final NetworkProbe probe;
  final String contentUrl;

  const AlertOptInPage({
    super.key,
    required this.vault,
    required this.beacons,
    required this.probe,
    required this.contentUrl,
  });

  @override
  State<AlertOptInPage> createState() => _AlertOptInPageState();
}

class _AlertOptInPageState extends State<AlertOptInPage> {
  bool _navigating = false;

  Future<void> _accept() async {
    if (_navigating) return;
    _navigating = true;
    final granted = await widget.beacons.askPermission();
    if (!granted) {
      final snooze = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          RuntimeProfile.pushPromoCooldownSec;
      await widget.vault.snoozePushPromo(snooze);
    }
    if (!mounted) return;
    _gotoShell();
  }

  Future<void> _skip() async {
    if (_navigating) return;
    _navigating = true;
    final snooze = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        RuntimeProfile.pushPromoCooldownSec;
    await widget.vault.snoozePushPromo(snooze);
    if (!mounted) return;
    _gotoShell();
  }

  Future<void> _gotoShell() async {
    await shell.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => shell.WebShellPage(
          startUrl: widget.contentUrl,
          vault: widget.vault,
          beacons: widget.beacons,
          probe: widget.probe,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final asset = orientation == Orientation.landscape
        ? 'assets/assets_webp/notify_horizontal.webp'
        : 'assets/assets_webp/notify_vertical.webp';

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
          if (orientation == Orientation.portrait)
            _PortraitButtons(onAccept: _accept, onSkip: _skip)
          else
            _LandscapeButtons(onAccept: _accept, onSkip: _skip),
        ],
      ),
    );
  }
}

class _PortraitButtons extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onSkip;
  const _PortraitButtons({required this.onAccept, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Positioned(
      left: size.width * 0.08,
      right: size.width * 0.08,
      bottom: size.height * 0.08,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AcceptButton(onTap: onAccept),
          const SizedBox(height: 14),
          _SkipButton(onTap: onSkip),
        ],
      ),
    );
  }
}

class _LandscapeButtons extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onSkip;
  const _LandscapeButtons({required this.onAccept, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Positioned(
      left: 0,
      right: 0,
      bottom: size.height * 0.07,
      child: Center(
        child: SizedBox(
          width: size.width * 0.36,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AcceptButton(onTap: onAccept, compact: true),
              const SizedBox(height: 8),
              _SkipButton(onTap: onSkip, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcceptButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  const _AcceptButton({required this.onTap, this.compact = false});

  @override
  State<_AcceptButton> createState() => _AcceptButtonState();
}

class _AcceptButtonState extends State<_AcceptButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, _) {
        final t = _shimmer.value;
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
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: widget.compact ? 11 : 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _pressed
                      ? const [Color(0xFF00B8D4), Color(0xFFC700A0)]
                      : const [Color(0xFF00E5FF), Color(0xFFFF00C8)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.35 + t * 0.4),
                    blurRadius: 20 + t * 14,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: const Color(0xFFFF00C8).withValues(alpha: 0.25 + t * 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'Accept',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.compact ? 16 : 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    shadows: const [
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkipButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  const _SkipButton({required this.onTap, this.compact = false});

  @override
  State<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<_SkipButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 90),
        opacity: _pressed ? 0.55 : 0.9,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.compact ? 4 : 6),
          child: Center(
            child: Text(
              'Skip',
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.compact ? 15 : 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
                shadows: const [
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
