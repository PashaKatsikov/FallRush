// One-off tool: converts the loading-screen PNGs to (lossless) WebP, downscaling
// oversized art to a sane phone resolution first to cut file size.
// Run with: dart run tool/convert_loading_webp.dart
import 'dart:io';
import 'package:image/image.dart' as img;

const maxDim = 4000; // keep native resolution (short side is already ~1080)

void main() {
  const names = [
    'Vertical_Loading_Screen',
    'Horizontal_Loading_Screen',
  ];
  for (final name in names) {
    final src = File('assets/assets_png/$name.png');
    if (!src.existsSync()) {
      stderr.writeln('SKIP (missing): $name');
      continue;
    }
    var im = img.decodePng(src.readAsBytesSync());
    if (im == null) {
      stderr.writeln('SKIP (decode failed): $name');
      continue;
    }
    final origW = im.width;
    final origH = im.height;

    if (im.width > maxDim || im.height > maxDim) {
      if (im.width >= im.height) {
        im = img.copyResize(im, width: maxDim);
      } else {
        im = img.copyResize(im, height: maxDim);
      }
    }

    final bytes = img.encodeWebP(im);
    final out = File('assets/assets_webp/$name.webp');
    out.writeAsBytesSync(bytes);
    final kb = (bytes.length / 1024).round();
    stdout.writeln(
        '$name: ${origW}x$origH -> ${im.width}x${im.height}  ($kb KB webp)');
  }
}
