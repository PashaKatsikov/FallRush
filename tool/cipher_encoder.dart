// Run with: dart run tool/cipher_encoder.dart
//
// Generates the masked byte lists referenced by lib/setup/* and
// lib/network/request_router.dart. Re-run after editing _seed in
// lib/secure/cipher.dart.
//
// ⚠️ Always use `dart run`, never PowerShell. PowerShell on
// Windows overflows 32-bit ints which corrupts the mask.
import 'dart:io';
// ignore: avoid_relative_lib_imports
import '../lib/secure/cipher.dart';

const _samples = <String, String>{
  'CONFIG_ENDPOINT': 'https://fallrussh.com/config.php',
  'GCD_HOST': 'https://gcdsdk.appsflyer.com',
  'GCD_PATH': '/install_data/v4.0/',
  'CHROME_VERSION': '141.0.7390.124',
  'WEBKIT_VERSION': '537.36',
  'APPSFLYER_DEV_KEY': 'E8svApiqC2v5kMWHBLBRth',
  'FIREBASE_PROJECT_NUMBER': '635154206809',
};

void main() {
  final mask = debugMaskCopy();
  stdout.writeln('// Mask length: ${mask.length}\n');

  _samples.forEach((label, plain) {
    final out = <int>[];
    final units = plain.codeUnits;
    for (var i = 0; i < units.length; i++) {
      out.add(units[i] ^ mask[i % mask.length]);
    }
    stdout.writeln('// $label = "$plain"');
    stdout.write('const $label = <int>[');
    for (var i = 0; i < out.length; i++) {
      if (i % 12 == 0) stdout.write('\n  ');
      stdout.write('0x${out[i].toRadixString(16).padLeft(2, '0')},');
      if (i % 12 != 11 && i != out.length - 1) stdout.write(' ');
    }
    stdout.writeln('\n];\n');
  });
}
