/// Persistent decision on which surface this user should see on
/// every launch. Decided once by the backend on first run.
enum LaunchPath {
  /// Backend approved a stream URL — open the WebView shell.
  stream('stream'),

  /// Backend declined — permanently show the in-app arcade.
  arcade('arcade'),

  /// No decision yet (very first launch).
  pending('pending');

  const LaunchPath(this.marker);

  final String marker;

  static LaunchPath restore(String? token) {
    if (token == null) return LaunchPath.pending;
    for (final p in LaunchPath.values) {
      if (p.marker == token) return p;
    }
    return LaunchPath.pending;
  }
}
