// ignore: unused_import
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
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check live in a try/catch so a broken config
  // file never crashes the app on first boot.
  //
  // ⚠️ DIAGNOSTIC: App Check временно выключен, пока ловим
  // «Application install not found». Если в Firebase Console включен
  // enforce App Check на Cloud Messaging / Firebase Installations и у
  // устройства нет debug-токена в консоли, любой Installations-запрос
  // отбивается 403 → install не регистрируется → пуш на полученный
  // FCM token возвращает ту самую ошибку. Включить обратно ПОСЛЕ
  // того, как пуши заработают, и зарегистрировать debug token из
  // logcat (Firebase Console → App Check → Apps → ⋮ → Manage debug
  // tokens).
  try {
    await Firebase.initializeApp();
    if (kDebugMode) {
      // ignore: avoid_print
      print('[main] Firebase.initializeApp() OK');
    }
    // await FirebaseAppCheck.instance.activate(
    //   androidProvider: kDebugMode
    //       ? AndroidProvider.debug
    //       : AndroidProvider.playIntegrity,
    // );
  } catch (e, st) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[main] Firebase.initializeApp() FAILED: $e\n$st');
    }
  }

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

  // ⚠️ Игровая часть (GameScreen) использует синглтон StorageService с
  // `late SharedPreferences _prefs`. В оригинальном шаблоне FallRush
  // его init() забыли вызвать здесь — поэтому при первом открытии
  // GameScreen вылетал `LateInitializationError: Field '_prefs@...'
  // has not been initialized` (красный экран). Инициализируем явно,
  // в одном ряду с SessionVault.
  await StorageService().init();

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
