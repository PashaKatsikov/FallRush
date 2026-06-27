import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'network/attribution_tracker.dart';
import 'network/beacon_center.dart';
import 'network/config_gateway.dart';
import 'network/network_probe.dart';
import 'network/request_router.dart';
import 'network/session_vault.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check live in a try/catch so a broken config
  // file never crashes the app on first boot.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await RequestRouter.instance.hydrate();

  final vault = SessionVault();
  await vault.warmUp();

  final probe = NetworkProbe();
  final attribution = AttributionTracker();
  final gateway = ConfigGateway(vault);
  final beacons = BeaconCenter(vault);

  runApp(FallRushApp(
    vault: vault,
    probe: probe,
    attribution: attribution,
    gateway: gateway,
    beacons: beacons,
  ));
}
