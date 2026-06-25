import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// Loads and caches the decoded sprites used by the game painter.
class GameAssets {
  static final GameAssets _instance = GameAssets._();
  factory GameAssets() => _instance;
  GameAssets._();

  late ui.Image ball;
  late ui.Image ballRed;
  late ui.Image bg1;
  late ui.Image bg2;
  late ui.Image blade;
  late ui.Image clock;
  late ui.Image lightning;
  late ui.Image shield;
  late ui.Image spark;
  late ui.Image spike;

  bool loaded = false;

  static const _dir = 'assets/assets_webp';

  Future<void> loadAll() async {
    if (loaded) return;

    final results = await Future.wait([
      _load('$_dir/ball_asset.webp'),
      _load('$_dir/ball_red_asset.webp'),
      _load('$_dir/bg_1_asset.webp'),
      _load('$_dir/bg_2_asset.webp'),
      _load('$_dir/blade_asset.webp'),
      _load('$_dir/clock_asset.webp'),
      _load('$_dir/lightning_asset.webp'),
      _load('$_dir/shield_asset.webp'),
      _load('$_dir/spark_asset.webp'),
      _load('$_dir/spike_asset.webp'),
    ]);

    ball = results[0];
    ballRed = results[1];
    bg1 = results[2];
    bg2 = results[3];
    blade = results[4];
    clock = results[5];
    lightning = results[6];
    shield = results[7];
    spark = results[8];
    spike = results[9];

    loaded = true;
  }

  Future<ui.Image> _load(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
