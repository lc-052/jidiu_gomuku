import 'package:flutter/material.dart';

/// 玩家枚举：黑方 / 白方
enum Player {
  black('Black', '黑方', Colors.black),
  white('White', '白方', Color(0xFFF5F5F5));

  final String en;
  final String cn;
  final Color color;

  const Player(this.en, this.cn, this.color);

  /// 转为 Flutter Color
  Color toColor() => color;

  /// 中文名称
  @override
  String toString() => cn;

  /// 获取对面玩家
  Player opponent() => this == Player.black ? Player.white : Player.black;
}

/// 棋盘格子状态
enum CellState {
  empty('空'),
  black('●'),
  white('○');

  final String symbol;

  const CellState(this.symbol);

  /// 从 Player 转换
  static CellState fromPlayer(Player player) =>
      player == Player.black ? CellState.black : CellState.white;

  /// 是否有效落子
  bool get isValid => this != CellState.empty;
}

/// 游戏整体状态
enum GameState {
  playing, // 对局进行中
  blackWon, // 黑方获胜
  whiteWon, // 白方获胜
  draw, // 平局（棋盘满）
}

/// 棋盘坐标位置
class Position {
  final int row;
  final int col;

  const Position({required this.row, required this.col});

  /// 判断两个位置是否相等
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position && row == other.row && col == other.col;

  @override
  int get hashCode => row.hashCode ^ col.hashCode;

  /// 深拷贝副本
  Position copyWith({int? row, int? col}) =>
      Position(row: row ?? this.row, col: col ?? this.col);

  @override
  String toString() => 'Position($row, $col)';
}

/// 棋盘尺寸枚举
enum BoardSize {
  standard(15, '标准 15x15'),
  small(9, '小棋盘 9x9'),
  large(19, '大棋盘 19x19');

  final int size;
  final String displayName;

  const BoardSize(this.size, this.displayName);

  /// 根据索引获取（用于 UI 选择器）
  static BoardSize fromIndex(int index) => [
        BoardSize.small,
        BoardSize.standard,
        BoardSize.large,
      ][index.clamp(0, 2)];
}

/// AI 难度等级
enum Difficulty {
  easy('简单'),
  medium('中等'),
  hard('困难');

  final String displayName;

  const Difficulty(this.displayName);
}

/// 走棋记录，用于悔棋和复盘
class MoveRecord {
  final Position position;
  final Player player;
  final DateTime time;

  /// 创建走棋记录。[time] 为 null 时自动使用当前时间
  MoveRecord({
    required this.position,
    required this.player,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveRecord &&
          position == other.position &&
          player == other.player &&
          time == other.time;

  @override
  int get hashCode => position.hashCode ^ player.hashCode ^ time.hashCode;

  /// 深拷贝副本
  MoveRecord copyWith({
    Position? position,
    Player? player,
    DateTime? time,
  }) =>
      MoveRecord(
        position: position ?? this.position,
        player: player ?? this.player,
        time: time ?? this.time,
      );
}
