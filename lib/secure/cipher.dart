import 'dart:typed_data';

// ─────────────────────────────────────────────────────────────
// Cipher: byte-stream unmasking helper for FallRush
// ─────────────────────────────────────────────────────────────
// Sensitive strings (config domain, attribution dev key, sender
// id, user-agent fragments) live as masked byte lists in code.
// The mask is derived from a project-specific phrase via:
//   FNV-1a 32-bit  →  xorshift32  →  24-byte stream
// The result feels structurally unlike a plain XOR/LCG codec,
// so the binary's static-analysis signature is unique per app.
//
// If you change `_seed` you MUST re-run tool/cipher_encoder.dart
// and replace every byte list referenced by `unmask(...)`.
// ─────────────────────────────────────────────────────────────

const List<int> _seed = <int>[
  0x66, 0x72, 0x4E, 0x65, 0x6F, 0x6E, 0x37, 0x78, // "frNeon7x"
];

const int _maskLength = 24;

Uint8List _spinMask() {
  var h = 0x811C9DC5;
  for (final byte in _seed) {
    h ^= byte;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }

  final out = Uint8List(_maskLength);
  var state = h == 0 ? 0xDEADBEEF : h;
  for (var i = 0; i < out.length; i++) {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= (state >> 17);
    state ^= (state << 5) & 0xFFFFFFFF;
    state &= 0xFFFFFFFF;
    out[i] = (state ^ (state >> 11) ^ (state >> 19)) & 0xFF;
  }
  return out;
}

final Uint8List _mask = _spinMask();

/// Restore a masked byte list to its original UTF-8 string.
String unmask(List<int> blob) {
  if (blob.isEmpty) return '';
  final raw = Uint8List(blob.length);
  for (var i = 0; i < blob.length; i++) {
    raw[i] = blob[i] ^ _mask[i % _mask.length];
  }
  return String.fromCharCodes(raw);
}

/// Returns the active 24-byte mask. Exposed only for the offline
/// encoder tool so it can xor plaintexts with the identical key.
Uint8List debugMaskCopy() => Uint8List.fromList(_mask);
