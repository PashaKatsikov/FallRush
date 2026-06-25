import 'package:flutter/material.dart';

/// Permanent, coin-bought upgrades. Each has a finite number of levels.
enum UpgradeId {
  heatShield,
  shieldDuration,
  magnet,
  coinValue,
  slowmoDuration,
  startShield,
}

class UpgradeInfo {
  final UpgradeId id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final int maxLevel;
  final int baseCost;

  const UpgradeInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.maxLevel,
    required this.baseCost,
  });

  /// Cost to go from [level] -> [level]+1. Returns -1 when maxed.
  int costForLevel(int level) {
    if (level >= maxLevel) return -1;
    return (baseCost * (1 + level * 0.85)).round();
  }
}

const List<UpgradeInfo> allUpgrades = [
  UpgradeInfo(
    id: UpgradeId.heatShield,
    name: 'Heat Shield',
    description: 'Walls heat the ball slower',
    icon: Icons.local_fire_department,
    color: Color(0xFFFF5252),
    maxLevel: 5,
    baseCost: 120,
  ),
  UpgradeInfo(
    id: UpgradeId.shieldDuration,
    name: 'Shield Power',
    description: 'Shield pickups last longer',
    icon: Icons.shield,
    color: Color(0xFF40C4FF),
    maxLevel: 5,
    baseCost: 150,
  ),
  UpgradeInfo(
    id: UpgradeId.magnet,
    name: 'Coin Magnet',
    description: 'Pull nearby coins toward you',
    icon: Icons.adjust,
    color: Color(0xFFFFD740),
    maxLevel: 5,
    baseCost: 140,
  ),
  UpgradeInfo(
    id: UpgradeId.coinValue,
    name: 'Coin Value',
    description: '+15% coins per level',
    icon: Icons.monetization_on,
    color: Color(0xFFFFC107),
    maxLevel: 5,
    baseCost: 160,
  ),
  UpgradeInfo(
    id: UpgradeId.slowmoDuration,
    name: 'Time Warp',
    description: 'Slow-mo pickups last longer',
    icon: Icons.hourglass_bottom,
    color: Color(0xFFB388FF),
    maxLevel: 4,
    baseCost: 170,
  ),
  UpgradeInfo(
    id: UpgradeId.startShield,
    name: 'Head Start',
    description: 'Begin each run shielded',
    icon: Icons.rocket_launch,
    color: Color(0xFF69F0AE),
    maxLevel: 3,
    baseCost: 200,
  ),
];

UpgradeInfo upgradeInfo(UpgradeId id) =>
    allUpgrades.firstWhere((u) => u.id == id);

// ─────────────────────────────────────────────────────────────
// SKINS — color variants tinting the single ball sprite.
// ─────────────────────────────────────────────────────────────

class SkinInfo {
  final String id;
  final String name;
  final Color tint;

  /// 0 = pure sprite, 1 = fully tinted. Lets us keep highlights.
  final double tintStrength;
  final int price;

  /// Unlocks automatically when the player reaches this level (0 = buyable).
  final int unlockLevel;

  const SkinInfo({
    required this.id,
    required this.name,
    required this.tint,
    this.tintStrength = 0.55,
    this.price = 0,
    this.unlockLevel = 0,
  });
}

const List<SkinInfo> allSkins = [
  SkinInfo(id: 'aqua', name: 'Aqua', tint: Color(0xFF00E5FF), tintStrength: 0.0),
  SkinInfo(id: 'magenta', name: 'Magenta', tint: Color(0xFFFF00C8), price: 500),
  SkinInfo(id: 'lime', name: 'Toxic', tint: Color(0xFF76FF03), price: 800),
  SkinInfo(id: 'gold', name: 'Gold', tint: Color(0xFFFFD700), price: 1500),
  SkinInfo(
      id: 'crimson', name: 'Crimson', tint: Color(0xFFFF1744), price: 2200),
  SkinInfo(
      id: 'violet',
      name: 'Nova',
      tint: Color(0xFF7C4DFF),
      price: 0,
      unlockLevel: 8),
  SkinInfo(
      id: 'rainbow',
      name: 'Spectrum',
      tint: Color(0xFFFFFFFF),
      tintStrength: 0.0,
      price: 5000),
];

SkinInfo skinById(String id) =>
    allSkins.firstWhere((s) => s.id == id, orElse: () => allSkins.first);

// ─────────────────────────────────────────────────────────────
// ZONES — depth-based biomes for variety / sense of progress.
// ─────────────────────────────────────────────────────────────

class ZoneInfo {
  final String name;
  final Color accent;
  final Color wallGlow;
  final bool useSecondBackground;

  const ZoneInfo({
    required this.name,
    required this.accent,
    required this.wallGlow,
    required this.useSecondBackground,
  });
}

const List<ZoneInfo> zones = [
  ZoneInfo(
      name: 'NEON SHAFT',
      accent: Color(0xFF00E5FF),
      wallGlow: Color(0xFF00B8D4),
      useSecondBackground: false),
  ZoneInfo(
      name: 'PLASMA CORE',
      accent: Color(0xFFFF00C8),
      wallGlow: Color(0xFFD500F9),
      useSecondBackground: true),
  ZoneInfo(
      name: 'VOID PIPE',
      accent: Color(0xFF7C4DFF),
      wallGlow: Color(0xFF651FFF),
      useSecondBackground: false),
  ZoneInfo(
      name: 'INFERNO',
      accent: Color(0xFFFF6D00),
      wallGlow: Color(0xFFFF3D00),
      useSecondBackground: true),
  ZoneInfo(
      name: 'CRYO LINE',
      accent: Color(0xFF18FFFF),
      wallGlow: Color(0xFF00E5FF),
      useSecondBackground: false),
];

const double zoneLength = 750.0;

ZoneInfo zoneForDepth(double meters) {
  final idx = (meters ~/ zoneLength) % zones.length;
  return zones[idx];
}

int zoneIndexForDepth(double meters) =>
    (meters ~/ zoneLength) % zones.length;

// ─────────────────────────────────────────────────────────────
// MISSIONS — lifetime-tracked goals that reward coins.
// ─────────────────────────────────────────────────────────────

enum MissionMetric { totalDistance, totalCoins, runsPlayed, shieldsUsed, bestRun }

class MissionTier {
  final MissionMetric metric;
  final String label;
  final IconData icon;
  final List<int> targets;
  final List<int> rewards;

  const MissionTier({
    required this.metric,
    required this.label,
    required this.icon,
    required this.targets,
    required this.rewards,
  });
}

const List<MissionTier> missionTiers = [
  MissionTier(
    metric: MissionMetric.totalDistance,
    label: 'Descend %d m total',
    icon: Icons.south,
    targets: [500, 2000, 6000, 15000, 40000],
    rewards: [100, 250, 500, 1000, 2500],
  ),
  MissionTier(
    metric: MissionMetric.totalCoins,
    label: 'Collect %d coins total',
    icon: Icons.monetization_on,
    targets: [200, 800, 2500, 7000, 18000],
    rewards: [120, 300, 600, 1200, 3000],
  ),
  MissionTier(
    metric: MissionMetric.bestRun,
    label: 'Reach %d m in one run',
    icon: Icons.flag,
    targets: [300, 700, 1300, 2200, 3500],
    rewards: [150, 350, 700, 1400, 3000],
  ),
  MissionTier(
    metric: MissionMetric.shieldsUsed,
    label: 'Grab %d shields',
    icon: Icons.shield,
    targets: [5, 20, 60, 150, 400],
    rewards: [100, 250, 550, 1100, 2600],
  ),
  MissionTier(
    metric: MissionMetric.runsPlayed,
    label: 'Play %d runs',
    icon: Icons.sports_esports,
    targets: [10, 40, 120, 300, 800],
    rewards: [80, 200, 450, 950, 2200],
  ),
];

// ─────────────────────────────────────────────────────────────
// PLAYER LEVEL / XP
// ─────────────────────────────────────────────────────────────

/// Total XP required to reach the start of [level] (level is 1-based).
int xpForLevel(int level) {
  // Cumulative quadratic curve.
  final l = level - 1;
  return (l * l * 60 + l * 90).round();
}

int levelForXp(int xp) {
  int level = 1;
  while (xp >= xpForLevel(level + 1)) {
    level++;
  }
  return level;
}

/// Coin reward granted when reaching [level].
int levelUpReward(int level) => 50 + level * 25;
