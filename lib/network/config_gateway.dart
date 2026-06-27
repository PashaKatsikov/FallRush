import 'dart:convert';
import '../setup/runtime_profile.dart';
import '../types/config_verdict.dart';
import 'request_router.dart';
import 'session_vault.dart';

/// Owns the POST /config request and the caching of the previous
/// answer. Always returns a [ConfigVerdict] — never throws.
class ConfigGateway {
  final SessionVault _vault;

  ConfigGateway(this._vault);

  Future<ConfigVerdict> askBackend(Map<String, dynamic> body) async {
    final endpoint = RuntimeProfile.configEndpoint;
    if (endpoint.isEmpty) {
      return const ConfigVerdict.failed('no-endpoint');
    }

    try {
      final response = await RequestRouter.instance
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: RuntimeProfile.configRequestTimeoutSec));

      if (response.statusCode != 200) {
        return ConfigVerdict.failed('http-${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const ConfigVerdict.failed('bad-shape');
      }

      final verdict = ConfigVerdict.fromMap(decoded);
      if (verdict.hasTarget) {
        await _vault.writeStreamUrl(verdict.target!);
        if (verdict.validUntil != null) {
          await _vault.writeStreamExpiry(verdict.validUntil!);
        }
      }
      return verdict;
    } catch (e) {
      return ConfigVerdict.failed(e.toString());
    }
  }

  Future<String?> cachedStreamUrl() => _vault.readStreamUrl();
}
