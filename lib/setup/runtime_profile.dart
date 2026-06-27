import 'analytics_keys.dart';
import 'endpoint_net.dart';
import 'static_pages.dart';

/// Aggregated read-only profile of project-level constants. Other
/// layers only ever talk to this — they never poke at the masked
/// byte arrays directly.
abstract final class RuntimeProfile {
  // ── Identity ──
  static const String bundleId = 'com.fallrush.fallrushgame';
  static const String storeId = 'com.fallrush.fallrushgame';
  static const String displayName = 'Fall Rush';

  // iOS App Store numeric id (kept empty — Android-only project).
  static const String iosAppStoreId = '';

  // ── Timings (per gray TZ) ──
  /// 3 days between "Skip" presses on the push opt-in screen.
  static const int pushPromoCooldownSec = 3 * 24 * 60 * 60;

  /// Wait window before retrying attribution via the GCD API when
  /// AppsFlyer first reports `af_status=Organic`.
  static const int organicRetryDelaySec = 5;

  /// Network-call ceiling for the config endpoint.
  static const int configRequestTimeoutSec = 15;

  // ── Lazy accessors that resolve from masked storage ──
  static String get configEndpoint => discoverConfigEndpoint();
  static String get attributionKey => unwrapAttributionKey();
  static String get senderId => unwrapSenderId();

  // ── Public urls ──
  static String get privacyPolicyUrl => fallRushPrivacyPolicyUrl;
  static String get supportUrl => fallRushSupportUrl;
  static String get homepageUrl => fallRushHomepageUrl;
}
