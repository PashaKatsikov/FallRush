// One-off tool: builds an adaptive-icon foreground by centering the square
// app art inside a transparent 1024x1024 canvas so it fits the Android
// adaptive-icon safe zone (~66%). Run with: dart run tool/gen_icon_foreground.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('assets/assets_png/icon.png').readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not read assets/assets_png/icon.png');
    exit(1);
  }

  const canvasSize = 1024;
  // Safe zone is the centre 66%. Round the art so masking looks clean.
  final artSize = (canvasSize * 0.62).round();

  final rounded = img.copyResize(src, width: artSize, height: artSize);
  _roundCorners(rounded, (artSize * 0.18).round());

  final canvas = img.Image(
      width: canvasSize, height: canvasSize, numChannels: 4);
  // transparent background
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final offset = ((canvasSize - artSize) / 2).round();
  img.compositeImage(canvas, rounded, dstX: offset, dstY: offset);

  File('assets/assets_png/icon_foreground.png')
      .writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Wrote assets/assets_png/icon_foreground.png');
}

void _roundCorners(img.Image image, int radius) {
  final w = image.width;
  final h = image.height;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double? dx, dy;
      if (x < radius && y < radius) {
        dx = (radius - x).toDouble();
        dy = (radius - y).toDouble();
      } else if (x >= w - radius && y < radius) {
        dx = (x - (w - radius - 1)).toDouble();
        dy = (radius - y).toDouble();
      } else if (x < radius && y >= h - radius) {
        dx = (radius - x).toDouble();
        dy = (y - (h - radius - 1)).toDouble();
      } else if (x >= w - radius && y >= h - radius) {
        dx = (x - (w - radius - 1)).toDouble();
        dy = (y - (h - radius - 1)).toDouble();
      }
      if (dx != null && dy != null) {
        final dist = (dx * dx + dy * dy);
        if (dist > radius * radius) {
          image.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
  }
}
