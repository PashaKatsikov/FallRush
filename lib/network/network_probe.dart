import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Two-phase connectivity check:
///   1. Cheap radio/Wi-Fi enumeration from connectivity_plus.
///   2. Real DNS lookup against a couple of well-known hosts so
///      captive portals and "fake online" states get caught.
class NetworkProbe {
  final Connectivity _channel = Connectivity();

  static const List<String> _resolveTargets = ['cloudflare.com', 'one.one.one.one'];

  Future<bool> isOnline() async {
    final radios = await _channel.checkConnectivity();
    final hasRadio = radios.any((r) => r != ConnectivityResult.none);
    if (!hasRadio) return false;

    for (final host in _resolveTargets) {
      try {
        final dns = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 3));
        if (dns.isNotEmpty && dns.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException catch (_) {
        // try next host
      } catch (_) {
        // try next host
      }
    }
    return false;
  }

  Stream<List<ConnectivityResult>> get changes => _channel.onConnectivityChanged;
}
