import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../types/launch_path.dart';

/// Disk-backed state used by the gray flow. Two underlying stores:
///   - SharedPreferences for flags / timestamps / mode marker
///   - FlutterSecureStorage for the saved URL and one-shot push URL
class SessionVault {
  static const _kPathMarker = 'fr_path_marker';
  static const _kSavedStreamUrl = 'fr_stream_url';
  static const _kStreamExpiresAt = 'fr_stream_expires';
  static const _kPushPromoCooldown = 'fr_push_promo_until';
  static const _kPushGranted = 'fr_push_granted';
  static const _kPushOsBlocked = 'fr_push_os_blocked';
  static const _kPendingPushUrl = 'fr_pending_push_url';

  late SharedPreferences _light;
  final FlutterSecureStorage _safe = const FlutterSecureStorage();

  Future<void> warmUp() async {
    _light = await SharedPreferences.getInstance();
  }

  // ── Launch path ──
  LaunchPath currentPath() => LaunchPath.restore(_light.getString(_kPathMarker));

  Future<void> commitPath(LaunchPath path) =>
      _light.setString(_kPathMarker, path.marker);

  // ── Saved stream URL (secure) ──
  Future<String?> readStreamUrl() => _safe.read(key: _kSavedStreamUrl);

  Future<void> writeStreamUrl(String url) =>
      _safe.write(key: _kSavedStreamUrl, value: url);

  // ── Stream-URL expiry timestamp ──
  int? streamExpiresAt() => _light.getInt(_kStreamExpiresAt);

  Future<void> writeStreamExpiry(int expiresAt) =>
      _light.setInt(_kStreamExpiresAt, expiresAt);

  bool streamExpired() {
    final at = streamExpiresAt();
    if (at == null) return true;
    return _nowSec() >= at;
  }

  // ── Push permission state ──
  bool pushAccepted() => _light.getBool(_kPushGranted) ?? false;

  Future<void> markPushAccepted(bool granted) =>
      _light.setBool(_kPushGranted, granted);

  /// After the OS-level dialog has been shown and dismissed/denied
  /// we mark it as blocked so the in-app promo never re-asks.
  bool pushBlockedByOs() => _light.getBool(_kPushOsBlocked) ?? false;

  Future<void> markPushBlockedByOs() =>
      _light.setBool(_kPushOsBlocked, true);

  int? pushPromoSnoozeUntil() => _light.getInt(_kPushPromoCooldown);

  Future<void> snoozePushPromo(int unixSec) =>
      _light.setInt(_kPushPromoCooldown, unixSec);

  /// Returns true if the opt-in screen should be displayed during
  /// the current cold boot.
  bool shouldShowPushPromo() {
    if (pushAccepted()) return false;
    if (pushBlockedByOs()) return false;
    final snooze = pushPromoSnoozeUntil();
    if (snooze == null) return true;
    return _nowSec() >= snooze;
  }

  // ── One-shot push URL (cold-tap only) ──
  Future<String?> peekPushUrl() => _safe.read(key: _kPendingPushUrl);

  Future<void> stashPushUrl(String? url) async {
    if (url == null) {
      await _safe.delete(key: _kPendingPushUrl);
    } else {
      await _safe.write(key: _kPendingPushUrl, value: url);
    }
  }

  Future<String?> takePushUrl() async {
    final url = await peekPushUrl();
    if (url != null) await _safe.delete(key: _kPendingPushUrl);
    return url;
  }

  static int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
