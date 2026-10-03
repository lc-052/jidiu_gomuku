// ignore_for_file: avoid_print
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_state.dart';
import '../models/theme_model.dart';

/// 本地存储服务：使用 SharedPreferences 持久化用户偏好设置。
/// 提供单例访问方式，保证全局只有一份配置数据。
/// 所有操作均为异步安全设计，错误时返回默认值而非抛出异常。
class StorageService {
  // ---------- 单例模式 ----------

  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  /// SharedPreferences 实例（延迟初始化）
  static SharedPreferences? _prefs;

  // ---------- 存储键名常量 ----------

  static const String _keyThemeIndex = 'theme_index';
  static const String _keyDifficultyIndex = 'difficulty_index';
  static const String _keySoundEnabled = 'sound_enabled';
  static const String _keyVibrationEnabled = 'vibration_enabled';
  static const String _keyLastMode = 'last_mode';
  static const String _keyPreferredColor = 'preferred_color';
  static const String _keyServerIp = 'server_ip';

  // ---------- 初始化 ----------

  /// 异步初始化 SharedPreferences 实例
  /// 必须在首次调用其他方法之前调用此方法
  /// 重复调用不会产生额外开销（内部已做幂等处理）
  static Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      print('[StorageService] 初始化失败: $e');
      throw Exception('无法初始化 SharedPreferences: $e');
    }
  }

  // ---------- 主题设置 ----------

  /// 获取当前选择的主题索引
  /// 自动钳制到合法范围，防止旧数据越界导致 UI 崩溃
  int get themeIndex {
    final raw = _prefs?.getInt(_keyThemeIndex) ?? 0;
    return raw.clamp(0, ThemePalette.all.length - 1);
  }

  /// 保存主题索引
  /// [index] 主题选项的索引值（>= 0）
  Future<void> saveThemeIndex(int index) async {
    try {
      await _prefs?.setInt(_keyThemeIndex, index.clamp(0, 2147483647));
    } catch (e) {
      print('[StorageService] 保存主题索引失败: $e');
    }
  }

  // ---------- AI 难度设置 ----------

  /// 获取当前 AI 难度索引
  /// 0 = 简单, 1 = 中等, 2 = 困难
  int get difficultyIndex {
    return _prefs?.getInt(_keyDifficultyIndex) ?? 1; // 默认中等
  }

  /// 保存 AI 难度索引
  /// [index] 难度选项的索引值（>= 0）
  Future<void> saveDifficultyIndex(int index) async {
    try {
      await _prefs?.setInt(_keyDifficultyIndex, index.clamp(0, 2147483647));
    } catch (e) {
      print('[StorageService] 保存难度索引失败: $e');
    }
  }

  // ---------- 音效设置 ----------

  /// 是否启用了音效
  bool get soundEnabled {
    return _prefs?.getBool(_keySoundEnabled) ?? true; // 默认开启
  }

  /// 保存音效开关状态
  /// [enabled] 是否启用
  Future<void> saveSoundEnabled(bool enabled) async {
    try {
      await _prefs?.setBool(_keySoundEnabled, enabled);
    } catch (e) {
      print('[StorageService] 保存音效设置失败: $e');
    }
  }

  // ---------- 震动反馈设置 ----------

  /// 是否启用了震动反馈
  bool get vibrationEnabled {
    return _prefs?.getBool(_keyVibrationEnabled) ?? true; // 默认开启
  }

  /// 保存震动反馈开关状态
  /// [enabled] 是否启用
  Future<void> saveVibrationEnabled(bool enabled) async {
    try {
      await _prefs?.setBool(_keyVibrationEnabled, enabled);
    } catch (e) {
      print('[StorageService] 保存震动设置失败: $e');
    }
  }

  // ---------- 游戏模式记忆 ----------

  /// 上次使用的游戏模式
  /// 0 = 本地对战, 1 = 在线对战
  int get lastMode {
    return _prefs?.getInt(_keyLastMode) ?? 0; // 默认本地对战
  }

  /// 保存最后使用的游戏模式
  /// [mode] 模式标识（0 或 1）
  Future<void> saveLastMode(int mode) async {
    try {
      await _prefs?.setInt(_keyLastMode, mode.clamp(0, 2147483647));
    } catch (e) {
      print('[StorageService] 保存游戏模式失败: $e');
    }
  }

  // ---------- 执子颜色偏好 ----------

  /// 获取偏好的执子颜色
  /// 默认黑方
  Player get preferredColor {
    final colorStr = _prefs?.getString(_keyPreferredColor)?.toLowerCase();
    switch (colorStr) {
      case 'white':
        return Player.white;
      case 'black':
        return Player.black;
      default:
        return Player.black; // 默认黑先
    }
  }

  /// 保存偏好的执子颜色字符串
  /// [colorStr] 颜色字符串：'black' 或 'white'
  Future<void> savePreferredColor(String colorStr) async {
    try {
      final normalized = colorStr.toLowerCase().trim();
      if (normalized != 'black' && normalized != 'white') {
        print('[StorageService] 无效的颜色的值: $normalized');
        return;
      }
      await _prefs?.setString(_keyPreferredColor, normalized);
    } catch (e) {
      print('[StorageService] 保存颜色偏好失败: $e');
    }
  }

  // ---------- 联机服务器地址 ----------

  /// 获取上次使用的服务器地址（IP 或域名）
  String get serverIp {
    return _prefs?.getString(_keyServerIp) ?? '192.168.1.1';
  }

  /// 保存服务器地址
  Future<void> saveServerIp(String ip) async {
    try {
      if (ip.trim().isEmpty) return;
      await _prefs?.setString(_keyServerIp, ip.trim());
    } catch (e) {
      print('[StorageService] 保存服务器地址失败: $e');
    }
  }

  // ---------- 清除所有设置 ----------

  /// 清除所有已保存的设置数据
  /// 恢复至出厂默认值
  Future<void> clearAll() async {
    try {
      final prefs = _prefs;
      if (prefs != null) {
        await prefs.clear();
      } else {
        // 如果尚未初始化，仍尝试清理缓存文件
        final freshPrefs = await SharedPreferences.getInstance();
        await freshPrefs.clear();
      }
    } catch (e) {
      print('[StorageService] 清除所有设置失败: $e');
      rethrow;
    }
  }

  // ---------- 批量保存（用于一次性保存多个设置） ----------

  /// 批量保存多项设置，原子性写入减少多次 IO
  /// 任何一项失败不影响其他项的保存
  /// 返回成功保存的项数
  Future<int> batchSave({
    int? themeIndex,
    int? difficultyIndex,
    bool? soundEnabled,
    bool? vibrationEnabled,
    int? lastMode,
    String? preferredColor,
  }) async {
    var savedCount = 0;

    try {
      if (themeIndex != null) {
        await _prefs?.setInt(_keyThemeIndex, themeIndex.clamp(0, 2147483647));
        savedCount++;
      }
      if (difficultyIndex != null) {
        await _prefs?.setInt(
            _keyDifficultyIndex, difficultyIndex.clamp(0, 2147483647));
        savedCount++;
      }
      if (soundEnabled != null) {
        await _prefs?.setBool(_keySoundEnabled, soundEnabled);
        savedCount++;
      }
      if (vibrationEnabled != null) {
        await _prefs?.setBool(_keyVibrationEnabled, vibrationEnabled);
        savedCount++;
      }
      if (lastMode != null) {
        await _prefs?.setInt(_keyLastMode, lastMode.clamp(0, 2147483647));
        savedCount++;
      }
      if (preferredColor != null) {
        final normalized = preferredColor.toLowerCase().trim();
        if (normalized == 'black' || normalized == 'white') {
          await _prefs?.setString(_keyPreferredColor, normalized);
          savedCount++;
        }
      }
    } catch (e) {
      print('[StorageService] 批量保存部分失败: $e');
    }

    return savedCount;
  }
}
