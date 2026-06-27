import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import '../setup/analytics_keys.dart';
import '../setup/runtime_profile.dart';
import 'request_router.dart';

/// Wraps the AppsFlyer SDK and produces the JSON body for the
/// config endpoint. The merging order is:
///
///   conversion-data ← deepLink (no overwrite) ← appOpen (no overwrite)
///   then platform-side overwrites are layered on top.
///
/// Organic false-positive handling: if the first attribution call
/// returns `af_status: Organic` the tracker pauses for
/// `RuntimeProfile.organicRetryDelaySec` and then refetches via the
/// GCD HTTP endpoint. The retry result, if available, becomes the
/// authoritative attribution payload.
class AttributionTracker {
  AppsflyerSdk? _native;

  Map<String, dynamic>? _attribution;
  Map<String, dynamic>? _deepLink;
  Map<String, dynamic>? _appOpen;

  final Completer<Map<String, dynamic>> _attributionGate = Completer();
  final Completer<void> _deepLinkGate = Completer();

  bool _booted = false;

  Future<void> boot() async {
    if (_booted) return;
    _booted = true;

    final devKey = RuntimeProfile.attributionKey;
    if (devKey.isEmpty) {
      _settleAttribution(<String, dynamic>{});
      _settleDeepLink();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: RuntimeProfile.iosAppStoreId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    _native = AppsflyerSdk(options);

    _native!.onInstallConversionData((data) async {
      final payload = _extract(data);
      if (payload['af_status'] == 'Organic') {
        await Future.delayed(
          Duration(seconds: RuntimeProfile.organicRetryDelaySec),
        );
        final retry = await _gcdRefresh();
        _attribution = retry ?? payload;
      } else {
        _attribution = payload;
      }
      _settleAttribution(_attribution!);
    });

    _native!.onAppOpenAttribution((data) {
      _appOpen = _extract(data);
    });

    _native!.onDeepLinking((result) {
      try {
        final deep = result.deepLink;
        if (deep != null) {
          _deepLink = deep.clickEvent;
        }
      } catch (_) {}
      _settleDeepLink();
    });

    try {
      await _native!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {}
  }

  /// Waits up to [timeoutSec] for the conversion-data callback; on
  /// timeout returns an empty map so the request still goes out.
  Future<Map<String, dynamic>> awaitAttribution({int timeoutSec = 30}) {
    return _attributionGate.future.timeout(
      Duration(seconds: timeoutSec),
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<void> awaitDeepLink({int timeoutSec = 5}) =>
      _deepLinkGate.future
          .timeout(Duration(seconds: timeoutSec), onTimeout: () {});

  Future<String?> readInstallUid() async {
    if (_native == null) return null;
    try {
      return await _native!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Builds the request body for the config endpoint following the
  /// merge order specified in the TZ. Device-side fields always win.
  Future<Map<String, dynamic>> assembleConfigBody({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};
    if (_attribution != null) body.addAll(_attribution!);
    _deepLink?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _appOpen?.forEach((k, v) => body.putIfAbsent(k, () => v));

    final uid = await readInstallUid();
    body['af_id'] = uid ?? '';
    body['bundle_id'] = RuntimeProfile.bundleId;
    body['store_id'] = RuntimeProfile.storeId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final sender = RuntimeProfile.senderId;
    if (sender.isNotEmpty) {
      body['firebase_project_id'] = sender;
    }

    if (kDebugMode) {
      debugPrint('[Attribution] body=${jsonEncode(body)}');
    }
    return body;
  }

  // ── Internals ────────────────────────────────────────────────

  Map<String, dynamic> _extract(dynamic raw) {
    if (raw is Map && raw['payload'] is Map) {
      return Map<String, dynamic>.from(raw['payload'] as Map);
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  void _settleAttribution(Map<String, dynamic> data) {
    if (!_attributionGate.isCompleted) {
      _attributionGate.complete(data);
    }
  }

  void _settleDeepLink() {
    if (!_deepLinkGate.isCompleted) {
      _deepLinkGate.complete();
    }
  }

  Future<Map<String, dynamic>?> _gcdRefresh() async {
    try {
      final devKey = RuntimeProfile.attributionKey;
      if (devKey.isEmpty) return null;
      final uid = await readInstallUid();
      if (uid == null || uid.isEmpty) return null;
      final appId =
          Platform.isIOS ? RuntimeProfile.iosAppStoreId : RuntimeProfile.bundleId;
      final url = buildGcdUrl(appId: appId, deviceId: uid);
      if (url.isEmpty) return null;

      final response = await RequestRouter.instance
          .get(
            Uri.parse(url),
            headers: {'authorization': 'Bearer $devKey'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }
}
