import 'package:shared_preferences/shared_preferences.dart';
import '../models/progression.dart';

/// Central persistence layer for all progression data.
class StorageService {
  static final StorageService _instance = StorageService._();
  factory StorageService() => _instance;
  StorageService._();

  late SharedPreferences _prefs;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _prefs = await SharedPreferences.getInstance();
    _ready = true;
  }

  // ── Currency ──
  int get coins => _prefs.getInt('coins') ?? 0;
  set coins(int v) => _prefs.setInt('coins', v < 0 ? 0 : v);

  void addCoins(int v) => coins = coins + v;
  bool spendCoins(int v) {
    if (coins < v) return false;
    coins = coins - v;
    return true;
  }

  // ── XP / Level ──
  int get xp => _prefs.getInt('xp') ?? 0;
  set xp(int v) => _prefs.setInt('xp', v);
  int get level => levelForXp(xp);

  /// Adds XP and returns the list of new levels reached (for level-up UI).
  List<int> addXp(int amount) {
    final before = level;
    xp = xp + amount;
    final after = level;
    final gained = <int>[];
    for (int l = before + 1; l <= after; l++) {
      gained.add(l);
      addCoins(levelUpReward(l));
    }
    return gained;
  }

  // ── Records ──
  int get highScore => _prefs.getInt('high_score') ?? 0;
  set highScore(int v) => _prefs.setInt('high_score', v);

  int get bestDistance => _prefs.getInt('best_distance') ?? 0;
  set bestDistance(int v) => _prefs.setInt('best_distance', v);

  // ── Upgrades ──
  int upgradeLevel(UpgradeId id) => _prefs.getInt('upg_${id.name}') ?? 0;
  void setUpgradeLevel(UpgradeId id, int level) =>
      _prefs.setInt('upg_${id.name}', level);

  // ── Skins ──
  String get activeSkin => _prefs.getString('active_skin') ?? 'aqua';
  set activeSkin(String id) => _prefs.setString('active_skin', id);

  List<String> get ownedSkins {
    final list = _prefs.getStringList('owned_skins') ?? ['aqua'];
    if (!list.contains('aqua')) list.add('aqua');
    return list;
  }

  void addOwnedSkin(String id) {
    final list = ownedSkins;
    if (!list.contains(id)) {
      list.add(id);
      _prefs.setStringList('owned_skins', list);
    }
  }

  // ── Lifetime mission stats ──
  int statTotalDistance() => _prefs.getInt('stat_total_distance') ?? 0;
  int statTotalCoins() => _prefs.getInt('stat_total_coins') ?? 0;
  int statRunsPlayed() => _prefs.getInt('stat_runs') ?? 0;
  int statShieldsUsed() => _prefs.getInt('stat_shields') ?? 0;
  int statBestRun() => bestDistance;

  int statForMetric(MissionMetric m) {
    switch (m) {
      case MissionMetric.totalDistance:
        return statTotalDistance();
      case MissionMetric.totalCoins:
        return statTotalCoins();
      case MissionMetric.runsPlayed:
        return statRunsPlayed();
      case MissionMetric.shieldsUsed:
        return statShieldsUsed();
      case MissionMetric.bestRun:
        return statBestRun();
    }
  }

  void recordRun({
    required int distance,
    required int coins,
    required int shields,
  }) {
    _prefs.setInt('stat_total_distance', statTotalDistance() + distance);
    _prefs.setInt('stat_total_coins', statTotalCoins() + coins);
    _prefs.setInt('stat_runs', statRunsPlayed() + 1);
    _prefs.setInt('stat_shields', statShieldsUsed() + shields);
  }

  // ── Mission tiers (which stage of each mission the player is on) ──
  int missionTierIndex(MissionMetric m) =>
      _prefs.getInt('mission_${m.name}') ?? 0;
  void setMissionTierIndex(MissionMetric m, int idx) =>
      _prefs.setInt('mission_${m.name}', idx);

  // ── Settings ──
  String get playerName => _prefs.getString('player_name') ?? 'Player';
  set playerName(String v) => _prefs.setString('player_name', v);

  bool get soundOn => _prefs.getBool('sound_on') ?? true;
  set soundOn(bool v) => _prefs.setBool('sound_on', v);

  // ── Daily bonus ──
  int get lastDailyClaim => _prefs.getInt('last_daily') ?? 0;
  set lastDailyClaim(int v) => _prefs.setInt('last_daily', v);

  bool get canClaimDaily {
    final last = DateTime.fromMillisecondsSinceEpoch(lastDailyClaim);
    final now = DateTime.now();
    return last.year != now.year ||
        last.month != now.month ||
        last.day != now.day;
  }
}
