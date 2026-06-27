import 'package:flutter/material.dart';

import 'network/attribution_tracker.dart';
import 'network/beacon_center.dart';
import 'network/config_gateway.dart';
import 'network/network_probe.dart';
import 'network/session_vault.dart';
import 'views/boot_orchestrator.dart';

class FallRushApp extends StatelessWidget {
  final SessionVault vault;
  final NetworkProbe probe;
  final AttributionTracker attribution;
  final ConfigGateway gateway;
  final BeaconCenter beacons;

  const FallRushApp({
    super.key,
    required this.vault,
    required this.probe,
    required this.attribution,
    required this.gateway,
    required this.beacons,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fall Rush',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05060F),
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF00C8),
          surface: Color(0xFF0C1024),
        ),
      ),
      home: BootOrchestrator(
        vault: vault,
        probe: probe,
        attribution: attribution,
        gateway: gateway,
        beacons: beacons,
      ),
    );
  }
}
