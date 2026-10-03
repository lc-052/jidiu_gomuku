/// 游戏模式枚举 —— 本地双人、在线对战、人机对战。
enum GameMode {
  local('local', '双人对战'), // 本地双人对战
  ai('ai', '人机对战'), // AI 人机对战
  online('online', '在线联机'); // 在线对战

  final String key;
  final String displayName;

  const GameMode(this.key, this.displayName);
}
