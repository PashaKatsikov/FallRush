import '../secure/cipher.dart';

// Masked attribution + push project credentials.
//
// To plug in real values, fill `tool/cipher_encoder.dart` with
// the plaintext and replace the lists below with the printed
// byte arrays. NEVER inline the plaintext.

// AppsFlyer Dev Key (masked).
const List<int> _devKeyBlob = <int>[
  0x25, 0x9f, 0x7d, 0x5f, 0xa8, 0x9d, 0x02, 0x2e, 0x17, 0x97, 0xed, 0x51,
  0x53, 0xa2, 0xb2, 0x2c, 0x10, 0xf4, 0x5b, 0xa6, 0xfc, 0x84,
];

// Firebase sender id / project number (masked).
const List<int> _projectIdBlob = <int>[
  0x56, 0x94, 0x3b, 0x18, 0xdc, 0xd9, 0x59, 0x6f, 0x62, 0x9d, 0xab, 0x5d,
];

// GCD host: https://gcdsdk.appsflyer.com
const List<int> _gcdHostBlob = <int>[
  0x08, 0xd3, 0x7a, 0x59, 0x9a, 0xd7, 0x44, 0x70, 0x33, 0xc6, 0xff, 0x17,
  0x5c, 0x84, 0xcb, 0x05, 0x22, 0xc8, 0x6a, 0x92, 0xe4, 0x95, 0x9f, 0xcd,
  0x4e, 0xc4, 0x61, 0x44,
];

// GCD path: /install_data/v4.0/
const List<int> _gcdPathBlob = <int>[
  0x4f, 0xce, 0x60, 0x5a, 0x9d, 0x8c, 0x07, 0x33, 0x0b, 0xc1, 0xfa, 0x10,
  0x59, 0xc0, 0x93, 0x50, 0x7c, 0x88, 0x36,
];

String unwrapAttributionKey() {
  if (_devKeyBlob.isEmpty) return '';
  return unmask(_devKeyBlob);
}

String unwrapSenderId() {
  if (_projectIdBlob.isEmpty) return '';
  return unmask(_projectIdBlob);
}

/// Build the GCD (Get Conversion Data) URL used as a fallback when
/// AppsFlyer initially reports `af_status=Organic`. Adds the app id
/// and the AppsFlyer install device id as query parameters.
String buildGcdUrl({required String appId, required String deviceId}) {
  if (_gcdHostBlob.isEmpty) return '';
  final base = unmask(_gcdHostBlob) + unmask(_gcdPathBlob);
  return '$base$appId?device_id=$deviceId';
}
