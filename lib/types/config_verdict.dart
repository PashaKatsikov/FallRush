/// Decoded payload returned by the config endpoint.
/// `ok=true` + non-null `target` ⇒ open WebView with that URL.
/// `ok=false` or no `target` ⇒ permanent arcade mode for this install.
class ConfigVerdict {
  final bool ok;
  final String? target;
  final String? reason;
  final int? validUntil;

  const ConfigVerdict({
    required this.ok,
    this.target,
    this.reason,
    this.validUntil,
  });

  /// Convenient short-circuit for the gateway when the binary lacks
  /// a config endpoint or fails to talk to it.
  const ConfigVerdict.failed(String why)
      : ok = false,
        target = null,
        reason = why,
        validUntil = null;

  factory ConfigVerdict.fromMap(Map<String, dynamic> raw) {
    return ConfigVerdict(
      ok: raw['ok'] == true,
      target: raw['url'] as String?,
      reason: raw['message'] as String?,
      validUntil: raw['expires'] is int ? raw['expires'] as int : null,
    );
  }

  bool get hasTarget => ok && (target != null) && target!.isNotEmpty;
}
