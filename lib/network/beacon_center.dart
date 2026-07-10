import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'session_vault.dart';

/// Background isolate entry-point. Must stay top-level and trivial.
@pragma('vm:entry-point')
Future<void> _bgBeaconSink(RemoteMessage _) async {
  // No work — OS draws the notification banner itself.
}

const String fallRushPushChannel = 'fallrush_push_channel';

/// Push pipeline: FCM ↔ local notifications ↔ session vault.
/// The "cold tap saves URL, warm tap delivers via callback" rule
/// from the TZ is preserved (see [_onColdTap] vs [_onWarmTap]).
class BeaconCenter {
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final SessionVault _vault;
  FirebaseMessaging? _fcm;
  String? _fcmToken;
  bool _alive = false;

  /// Fired when a push containing a `url` field is opened or tapped
  /// while the app is alive. NOT fired on cold taps (those are saved
  /// to the vault for the boot orchestrator to pick up).
  void Function(String url)? onLiveUrl;

  /// Fired when FCM rotates the token. The boot orchestrator
  /// re-POSTs the config endpoint with the new token.
  void Function(String token)? onTokenRotated;

  BeaconCenter(this._vault);

  String? get token => _fcmToken;

  Future<void> wakeUp() async {
    if (_alive) return;
    try {
      await Firebase.initializeApp();
      _fcm = FirebaseMessaging.instance;
      _log('Firebase initialized, FirebaseMessaging instance acquired');

      FirebaseMessaging.onBackgroundMessage(_bgBeaconSink);

      await _setUpLocal();
      _log('Local notification channel ready: $fallRushPushChannel');

      _fcmToken = await _fcm!.getToken();
      _logToken('initial', _fcmToken);

      _fcm!.onTokenRefresh.listen((t) {
        _fcmToken = t;
        _logToken('rotated', t);
        onTokenRotated?.call(t);
      });

      FirebaseMessaging.onMessage.listen(_drawForegroundBanner);
      FirebaseMessaging.onMessageOpenedApp.listen(_onWarmTap);

      final initial = await _fcm!.getInitialMessage();
      if (initial != null) _onColdTap(initial);

      _alive = true;
      _log('wakeUp complete (alive=true)');
    } catch (e, st) {
      _log('wakeUp FAILED: $e\n$st');
      // No Firebase config — gracefully run without push.
    }
  }

  /// Запрос разрешения POST_NOTIFICATIONS.
  ///
  /// На референсном Samsung A55 (One UI 6, Android 15) метод
  /// `FirebaseMessaging.requestPermission()` возвращает `denied`
  /// без показа системного диалога, даже если разрешение никогда не
  /// запрашивалось (баг плагина firebase_messaging 15.x для OEM,
  /// которые делегируют permission delegate своему собственному
  /// NotificationManager). Лечится явным вызовом
  /// `AndroidFlutterLocalNotificationsPlugin.requestNotificationsPermission()`
  /// — он внутри плагина 18.0.1 дёргает нативный
  /// `ActivityCompat.requestPermissions(POST_NOTIFICATIONS, …)`,
  /// единственный API, который физически показывает системный диалог
  /// на API 33+.
  Future<bool> askPermission() async {
    if (_fcm == null) {
      _log('askPermission: _fcm == null (Firebase не инициализирован) '
          '→ диалог не показать, return false');
      return false;
    }

    // 1) Эталонный путь greensun_corp/push_notification_service.dart.
    var settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    var granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    _log('askPermission: FirebaseMessaging status=${settings.authorizationStatus}');

    // 2) Fallback для Samsung One UI / MIUI / некоторых HyperOS,
    //    где (1) не показывает диалог. Канал в _setUpLocal() уже
    //    создан, плагин готов.
    if (!granted && Platform.isAndroid) {
      final plugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final androidGranted =
          await plugin?.requestNotificationsPermission() ?? false;
      _log('askPermission: native POST_NOTIFICATIONS fallback granted=$androidGranted');
      if (androidGranted) {
        granted = true;
        settings = await _fcm!.getNotificationSettings();
      }
    }

    await _vault.markPushAccepted(granted);
    if (!granted &&
        settings.authorizationStatus == AuthorizationStatus.denied) {
      await _vault.markPushBlockedByOs();
    }

    // Часть OEM (Pixel 8/9, Samsung S22+) откладывают создание FID
    // до тех пор, пока permission не granted. Дёргаем getToken
    // повторно — это даёт первый РАБОЧИЙ для пушей токен.
    if (granted && (_fcmToken == null || _fcmToken!.isEmpty)) {
      try {
        _fcmToken = await _fcm!.getToken();
        _logToken('post-permission', _fcmToken);
      } catch (e) {
        _log('getToken after grant FAILED: $e');
      }
    }
    return granted;
  }

  // ── logging helpers ────────────────────────────────────────────────
  // Все сообщения идут одним фиксированным тегом, токен оформлен
  // отдельным баннером, чтобы grep'ать его одной командой:
  //   adb logcat -d | findstr "FCM TOKEN"
  // ----------------------------------------------------------------

  static const String _logTag = 'BEACON';

  void _log(String message) {
    if (!kDebugMode) return;
    // ignore: avoid_print
    print('[$_logTag] $message');
  }

  void _logToken(String label, String? token) {
    if (!kDebugMode) return;
    final body = (token == null || token.isEmpty)
        ? '<NULL — FCM did not return a token>'
        : token;
    // ignore: avoid_print
    print('[$_logTag] =========== FCM TOKEN ($label) ===========\n'
        '$body\n'
        '==========================================');
  }

  // ── internals ───────────────────────────────────────────────

  Future<void> _setUpLocal() async {
    const android = AndroidInitializationSettings('@drawable/ic_push_flame');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            final url = decoded['url'] as String?;
            if (url != null && url.isNotEmpty) onLiveUrl?.call(url);
          }
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final plugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await plugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          fallRushPushChannel,
          'Fall Rush Updates',
          description: 'Promo bursts, score reminders, special offers.',
          importance: Importance.high,
        ),
      );
    }
  }

  Future<void> _drawForegroundBanner(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return;
    if (!Platform.isAndroid) return;

    final imageUrl = _pickImageUrl(message);
    if (kDebugMode) {
      // ignore: avoid_print
      print('[BeaconCenter] foreground push — imageUrl=$imageUrl, '
          'data=${message.data}');
    }

    AndroidNotificationDetails? details;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      final bytes = await _grabBytes(imageUrl);
      if (bytes != null) {
        final bitmap = ByteArrayAndroidBitmap(bytes);
        details = AndroidNotificationDetails(
          fallRushPushChannel,
          'Fall Rush Updates',
          channelDescription:
              'Promo bursts, score reminders, special offers.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_push_flame',
          largeIcon: bitmap,
          styleInformation: BigPictureStyleInformation(
            bitmap,
            largeIcon: bitmap,
            hideExpandedLargeIcon: true,
            contentTitle: notif.title,
            summaryText: notif.body,
            htmlFormatContentTitle: false,
            htmlFormatSummaryText: false,
          ),
        );
      } else if (kDebugMode) {
        // ignore: avoid_print
        print('[BeaconCenter] failed to download push image: $imageUrl');
      }
    }

    details ??= const AndroidNotificationDetails(
      fallRushPushChannel,
      'Fall Rush Updates',
      channelDescription:
          'Promo bursts, score reminders, special offers.',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_push_flame',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    final payload = message.data.isNotEmpty ? jsonEncode(message.data) : null;
    await _local.show(
      notif.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  /// FCM может прислать URL картинки в разных местах: внутри `notification`
  /// (как `android.image` / `apns-fcm-options.image`) или в кастомном
  /// `data`-payload (`image`, `imageUrl`, `picture`, `fcm_options.image`).
  /// Перебираем все известные варианты, чтобы пуш не остался без картинки.
  String? _pickImageUrl(RemoteMessage message) {
    final notif = message.notification;
    final fromNotif = notif?.android?.imageUrl ?? notif?.apple?.imageUrl;
    if (fromNotif != null && fromNotif.isNotEmpty) return fromNotif;

    final data = message.data;
    for (final key in const [
      'image',
      'imageUrl',
      'image_url',
      'picture',
      'big_picture',
      'fcm_options.image',
    ]) {
      final raw = data[key];
      if (raw is String && raw.isNotEmpty) return raw;
    }

    final opts = data['fcm_options'];
    if (opts is Map && opts['image'] is String) {
      final raw = opts['image'] as String;
      if (raw.isNotEmpty) return raw;
    }
    return null;
  }

  void _onColdTap(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      _vault.stashPushUrl(url);
    }
  }

  void _onWarmTap(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      onLiveUrl?.call(url);
    }
  }

  Future<Uint8List?> _grabBytes(String url) async {
    // Голый http без подменённого User-Agent — некоторые CDN отдают
    // картинку только обычному клиенту и ругаются на «мобильный» UA
    // из RequestRouter.
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BeaconCenter] image fetch failed '
            'status=${response.statusCode} url=$url');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BeaconCenter] image fetch error: $e ($url)');
      }
    }
    return null;
  }
}
