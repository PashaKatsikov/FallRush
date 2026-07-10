import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../network/beacon_center.dart';
import '../network/network_probe.dart';
import '../network/request_router.dart';
import '../network/session_vault.dart';
import 'offline_lapse_page.dart';

/// Called via deferred import before navigating into [WebShellPage].
/// Currently a no-op; placeholder for future webview pre-warming.
Future<void> primeWebShell() async {}

/// Full-screen WebView. Handles:
///   - immersive system UI
///   - both orientations
///   - back navigates webview history (never exits)
///   - connectivity drop → OfflineLapsePage
///   - foreground push tap → loadRequest
///   - file picker for <input type=file>
///   - third-party cookies + autoplay video
///   - too-many-redirects retry (up to 3)
///   - keyboard above input field JS shim
///   - safe-area override JS shim
class WebShellPage extends StatefulWidget {
  final String startUrl;
  final SessionVault vault;
  final BeaconCenter beacons;
  final NetworkProbe probe;

  const WebShellPage({
    super.key,
    required this.startUrl,
    required this.vault,
    required this.beacons,
    required this.probe,
  });

  @override
  State<WebShellPage> createState() => _WebShellPageState();
}

class _WebShellPageState extends State<WebShellPage>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _spinning = true;
  bool _offlineShown = false;
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  String? _lastMainFrameUrl;
  int _redirectRetries = 0;

  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applyImmersive();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applyImmersive();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(RequestRouter.instance.userAgentString)
      ..setBackgroundColor(const Color(0xFF05060F))
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _spinning = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _spinning = false);
          _redirectRetries = 0;
          _patchSafeArea();
          _patchKeyboardScroll();
        },
        onWebResourceError: _handleResourceError,
        onHttpError: (_) {},
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final s = uri.scheme;
          if (s == 'http' ||
              s == 'https' ||
              s == 'about' ||
              s == 'data' ||
              s == 'blob') {
            if (request.isMainFrame) _lastMainFrameUrl = request.url;
            return NavigationDecision.navigate;
          }
          _kickToExternalApp(uri);
          return NavigationDecision.prevent;
        },
      ));

    _wireUpAndroid();
    _controller.loadRequest(Uri.parse(widget.startUrl));

    widget.beacons.onLiveUrl = (url) {
      if (mounted) _controller.loadRequest(Uri.parse(url));
    };

    _netSub = widget.probe.changes.listen((results) {
      if (results.every((r) => r == ConnectivityResult.none)) {
        _maybeShowOffline();
      }
    });
  }

  void _wireUpAndroid() {
    if (!Platform.isAndroid) return;
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;

    platform.setMediaPlaybackRequiresUserGesture(false);
    platform.setOnShowFileSelector(_onShowFilePicker);

    final cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(platform, true);
  }

  Future<List<String>> _onShowFilePicker(FileSelectorParams params) async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        return result.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(f.path!).toString())
            .toList(growable: false);
      }
    } catch (_) {}
    return const <String>[];
  }

  void _handleResourceError(WebResourceError error) {
    if (error.isForMainFrame == false) return;

    final descLower = error.description.toLowerCase();
    final isRedirectLoop = descLower.contains('too_many_redirects') ||
        descLower.contains('too many redirects') ||
        error.errorCode == -1007 ||
        error.errorCode == -9;

    if (isRedirectLoop &&
        _lastMainFrameUrl != null &&
        _redirectRetries < 3) {
      _redirectRetries++;
      _controller.loadRequest(Uri.parse(_lastMainFrameUrl!));
      return;
    }

    _maybeShowOffline();
  }

  Future<void> _maybeShowOffline() async {
    if (_offlineShown) return;
    final online = await widget.probe.isOnline();
    if (online || !mounted) return;
    _offlineShown = true;

    final currentUrl = await _controller.currentUrl() ?? widget.startUrl;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineLapsePage(
          revival: (_) => WebShellPage(
            startUrl: currentUrl,
            vault: widget.vault,
            beacons: widget.beacons,
            probe: widget.probe,
          ),
        ),
      ),
    );
  }

  Future<void> _kickToExternalApp(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _patchKeyboardScroll() {
    _controller.runJavaScript('''
(function() {
  if (window.__frKbPatch) return;
  window.__frKbPatch = true;

  var isInput = function(n) {
    return n && (n.tagName === 'INPUT' || n.tagName === 'TEXTAREA' || n.isContentEditable);
  };

  var scrollFocused = function() {
    var n = document.activeElement;
    if (!isInput(n)) return;
    var vv = window.visualViewport;
    if (vv) {
      var box = n.getBoundingClientRect();
      var bottom = vv.offsetTop + vv.height;
      if (box.bottom > bottom - 20 || box.top < vv.offsetTop) {
        n.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      n.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  };

  document.addEventListener('focusin', function(e) {
    if (isInput(e.target)) setTimeout(scrollFocused, 350);
  });

  if (window.visualViewport) {
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var h = window.visualViewport.height;
      if (h < prev) setTimeout(scrollFocused, 120);
      prev = h;
    });
  }
})();
''');
  }

  void _patchSafeArea() {
    _controller.runJavaScript(r'''
(function() {
  if (window.__frSafeAreaPatch) return;
  window.__frSafeAreaPatch = true;

  var TAG = '__frSafeAreaCss';
  var CSS =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-right:0px!important;' +
      '--safe-bottom:0px!important;--safe-left:0px!important;' +
    '}' +
    '.gameview-mobile-header,.app-header{' +
      'padding-top:0!important;' +
      'margin-top:0!important;' +
    '}';

  function keyboardOpen() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }

  function ensure() {
    if (keyboardOpen()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta && !/viewport-fit\s*=\s*contain/i.test(meta.getAttribute('content') || '')) {
      var content = (meta.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      meta.setAttribute('content', content + (content ? ', ' : '') + 'viewport-fit=contain');
    }
    var tag = document.getElementById(TAG);
    if (!tag) {
      tag = document.createElement('style');
      tag.id = TAG;
      head.appendChild(tag);
    }
    if (tag.textContent !== CSS) tag.textContent = CSS;
    if (head.lastElementChild !== tag) head.appendChild(tag);
  }

  ensure();
  ['pushState', 'replaceState'].forEach(function(name) {
    var orig = history[name];
    history[name] = function() {
      var r = orig.apply(this, arguments);
      setTimeout(ensure, 80);
      setTimeout(ensure, 400);
      return r;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(ensure, 80); });
  setInterval(ensure, 2500);
})();
''');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _netSub?.cancel();
    widget.beacons.onLiveUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<bool> _backHandler() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;

    // In portrait: only compensate the status-bar (top notch).
    // In landscape: honour all four sides so the camera cutout and
    // rounded corners never clip WebView content.
    final padding = isLandscape
        ? EdgeInsets.fromLTRB(
            mq.viewPadding.left,
            mq.viewPadding.top,
            mq.viewPadding.right,
            mq.viewPadding.bottom,
          )
        : EdgeInsets.only(top: mq.viewPadding.top);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _backHandler();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: padding,
              child: WebViewWidget(controller: _controller),
            ),
            if (_spinning)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
