import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import '../secure/cipher.dart';

// Masked Chrome / WebKit version snippets used by the on-the-wire
// User-Agent. They're masked rather than literal so a `strings`
// dump of the binary doesn't surface obvious version numbers.
//
// Plain → "141.0.7390.124"
const List<int> _chromeBlob = <int>[
  0x51, 0x93, 0x3f, 0x07, 0xd9, 0xc3, 0x5c, 0x6c, 0x6d, 0x95, 0xb5, 0x55,
  0x0a, 0xdb,
];

// Plain → "537.36"
const List<int> _webkitBlob = <int>[
  0x55, 0x94, 0x39, 0x07, 0xda, 0xdb,
];

/// HTTP layer that pretends to be a real Chrome/Safari mobile browser
/// on every outbound request. The exact User-Agent string is built
/// from live device facts (model, brand, sdk) merged with the masked
/// Chrome/WebKit version tags above.
class RequestRouter extends http.BaseClient {
  RequestRouter._();

  static final RequestRouter instance = RequestRouter._();

  final http.Client _delegate = http.Client();
  String _ua = 'Mozilla/5.0';

  String get userAgentString => _ua;

  /// Pull device facts then craft a UA that matches the local OS.
  /// Safe to call multiple times — only the first invocation does work.
  Future<void> hydrate() async {
    if (_ua != 'Mozilla/5.0') return;
    final chromeVer = _chromeBlob.isEmpty ? '141.0.0.0' : unmask(_chromeBlob);
    final webkitVer = _webkitBlob.isEmpty ? '537.36' : unmask(_webkitBlob);

    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        final api = a.version.sdkInt;
        final brand = a.brand.isEmpty ? 'Google' : a.brand;
        final model = a.model.isEmpty ? 'Pixel 8' : a.model;
        final buildId = (a.display.isNotEmpty ? a.display : a.id).isEmpty
            ? 'TQ3A.230901.001'
            : (a.display.isNotEmpty ? a.display : a.id);
        _ua = 'Mozilla/5.0 (Linux; Android $api; $brand $model '
            'Build/$buildId) AppleWebKit/$webkitVer (KHTML, like Gecko) '
            'Chrome/$chromeVer Mobile Safari/$webkitVer';
      } else if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        final osVer = i.systemVersion.replaceAll('.', '_');
        _ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS $osVer like Mac OS X) '
            'AppleWebKit/$webkitVer (KHTML, like Gecko) '
            'Version/${i.systemVersion} Mobile/15E148 Safari/$webkitVer';
      }
    } catch (_) {
      _ua = 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UQ1A.240105.004) '
          'AppleWebKit/$webkitVer (KHTML, like Gecko) '
          'Chrome/$chromeVer Mobile Safari/$webkitVer';
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => _ua);
    request.headers.putIfAbsent('Accept-Language', () => 'en-US,en;q=0.9');
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();
}
