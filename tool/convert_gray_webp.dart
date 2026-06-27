// One-off helper: re-encodes the source PNGs for the no-internet
// and push opt-in screens into compact lossy webp files, then
// drops them under assets/assets_webp/ with the names referenced
// by lib/views/*.
//
// Run with: dart run tool/convert_gray_webp.dart
import 'dart:io';
import 'package:image/image.dart' as img;

const _jobs = <_Job>[
  _Job('Vertical_Nowifi_Screen', 'nowifi_vertical', 2400),
  _Job('Horizontal_Nowifi_Screen', 'nowifi_horizontal', 2400),
  _Job('Vertical_Notifications_Screen', 'notify_vertical', 2400),
  _Job('Horizontal_Notifications_Screen', 'notify_horizontal', 2400),
];

class _Job {
  final String inName;
  final String outName;
  final int longSideCap;
  const _Job(this.inName, this.outName, this.longSideCap);
}

void main() {
  for (final job in _jobs) {
    final inFile = File('assets/assets_png/${job.inName}.png');
    if (!inFile.existsSync()) {
      stderr.writeln('Missing: ${inFile.path}');
      continue;
    }
    var image = img.decodePng(inFile.readAsBytesSync());
    if (image == null) {
      stderr.writeln('Decode failed: ${inFile.path}');
      continue;
    }

    final w = image.width;
    final h = image.height;
    if (w > job.longSideCap || h > job.longSideCap) {
      if (w >= h) {
        image = img.copyResize(image, width: job.longSideCap);
      } else {
        image = img.copyResize(image, height: job.longSideCap);
      }
    }

    final bytes = img.encodeWebP(image);
    final out = File('assets/assets_webp/${job.outName}.webp');
    out.writeAsBytesSync(bytes);
    stdout.writeln(
      '${job.inName}: ${w}x$h -> ${image.width}x${image.height}  (${(bytes.length / 1024).round()} KB)',
    );
  }
}
