import 'package:flutter/material.dart';

/// 主题调色板数据类，描述一套完整的棋盘配色方案
class ThemePalette {
  /// 主题名称
  final String name;

  /// 主色调（用于按钮、高亮元素）
  final Color primaryColor;

  /// 辅助色（用于次要操作、装饰）
  final Color secondaryColor;

  /// 边框颜色（棋盘外框）
  final Color borderColor;

  /// 网格线颜色
  final Color gridColor;

  /// 页面背景色
  final Color bgColor;

  /// 棋盘底色
  final Color boardBgColor;

  /// 黑棋渐变起始色
  final List<Color> blackStoneGrad1;

  /// 黑棋渐变结束色
  final List<Color> blackStoneGrad2;

  /// 白棋渐变起始色
  final List<Color> whiteStoneGrad1;

  /// 白棋渐变结束色
  final List<Color> whiteStoneGrad2;

  /// 文字颜色
  final Color textColor;

  const ThemePalette({
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.borderColor,
    required this.gridColor,
    required this.bgColor,
    required this.boardBgColor,
    required this.blackStoneGrad1,
    required this.blackStoneGrad2,
    required this.whiteStoneGrad1,
    required this.whiteStoneGrad2,
    required this.textColor,
  });

  /// 深拷贝副本
  ThemePalette copyWith({
    String? name,
    Color? primaryColor,
    Color? secondaryColor,
    Color? borderColor,
    Color? gridColor,
    Color? bgColor,
    Color? boardBgColor,
    List<Color>? blackStoneGrad1,
    List<Color>? blackStoneGrad2,
    List<Color>? whiteStoneGrad1,
    List<Color>? whiteStoneGrad2,
    Color? textColor,
  }) =>
      ThemePalette(
        name: name ?? this.name,
        primaryColor: primaryColor ?? this.primaryColor,
        secondaryColor: secondaryColor ?? this.secondaryColor,
        borderColor: borderColor ?? this.borderColor,
        gridColor: gridColor ?? this.gridColor,
        bgColor: bgColor ?? this.bgColor,
        boardBgColor: boardBgColor ?? this.boardBgColor,
        blackStoneGrad1: blackStoneGrad1 ?? this.blackStoneGrad1,
        blackStoneGrad2: blackStoneGrad2 ?? this.blackStoneGrad2,
        whiteStoneGrad1: whiteStoneGrad1 ?? this.whiteStoneGrad1,
        whiteStoneGrad2: whiteStoneGrad2 ?? this.whiteStoneGrad2,
        textColor: textColor ?? this.textColor,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ThemePalette && name == other.name;

  @override
  int get hashCode => name.hashCode;

// ---------- 6套预定义主题 ----------

  /// 经典黑白 — 传统围棋风格
  static const classicBlackWhite = ThemePalette._private(
    name: '经典黑白',
    primaryColor: Colors.black,
    secondaryColor: Color(0xFF9E9E9E),
    borderColor: Color(0xFF5D4037),
    gridColor: Color(0xFF333333),
    bgColor: Color(0xFFF5F5DC),
    boardBgColor: Color(0xFFDEB887),
    blackStoneGrad1: [Colors.black, Color(0xFF2A2A2A)],
    blackStoneGrad2: [Color(0xFF1A1A1A), Colors.black],
    whiteStoneGrad1: [Color(0xFFFFFEF0), Color(0xFFF8F8E8)],
    whiteStoneGrad2: [Color(0xFFF0F0E0), Color(0xFFFAFAF0)],
    textColor: Color(0xFF333333),
  );

  /// 星空蓝红 — 深邃宇宙风
  static const cosmicBlueRed = ThemePalette._private(
    name: '星空蓝红',
    primaryColor: Color(0xFF6A1B9A),
    secondaryColor: Color(0xFFE91E63),
    borderColor: Color(0xFF1A237E),
    gridColor: Color(0xFF311B92),
    bgColor: Color(0xFF1A1A2E),
    boardBgColor: Color(0xFF16213E),
    blackStoneGrad1: [Color(0xFF4A148C), Color(0xFF1A237E)],
    blackStoneGrad2: [Color(0xFF6A1B9A), Color(0xFFAA00FF)],
    whiteStoneGrad1: [Color(0xFFE0B0FF), Color(0xFFDDA0DD)],
    whiteStoneGrad2: [Color(0xFFF0E0FF), Color(0xFFE8D0F0)],
    textColor: Color(0xFFE0E0E0),
  );

  /// 翡翠金翠 — 中式典雅风
  static const emeraldGold = ThemePalette._private(
    name: '翡翠金翠',
    primaryColor: Color(0xFF00695C),
    secondaryColor: Color(0xFFFFC107),
    borderColor: Color(0xFF1B5E20),
    gridColor: Color(0xFF2E7D32),
    bgColor: Color(0xFFF1F8E9),
    boardBgColor: Color(0xFFC8E6C9),
    blackStoneGrad1: [Color(0xFF1B5E20), Color(0xFF004D40)],
    blackStoneGrad2: [Color(0xFF00695C), Color(0xFF00897B)],
    whiteStoneGrad1: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
    whiteStoneGrad2: [Color(0xFFFFFFFF), Color(0xFFE8F5E9)],
    textColor: Color(0xFF1B5E20),
  );

  /// 霓虹紫青 — 赛博朋克风
  static const neonPurpleCyan = ThemePalette._private(
    name: '霓虹紫青',
    primaryColor: Color(0xFF7C4DFF),
    secondaryColor: Color(0xFF18FFFF),
    borderColor: Color(0xFF651FFF),
    gridColor: Color(0xFF304FFE),
    bgColor: Color(0xFF0D0D2B),
    boardBgColor: Color(0xFF1A1A3E),
    blackStoneGrad1: [Color(0xFF304FFE), Color(0xFF651FFF)],
    blackStoneGrad2: [Color(0xFF7C4DFF), Color(0xFFB388FF)],
    whiteStoneGrad1: [Color(0xFF18FFFF), Color(0xFF00BCD4)],
    whiteStoneGrad2: [Color(0xFF84FFFF), Color(0xFF18FFFF)],
    textColor: Color(0xFFE0E0E0),
  );

  /// 落日橙粉 — 温暖黄昏风
  static const sunsetOrangePink = ThemePalette._private(
    name: '落日橙粉',
    primaryColor: Color(0xFFFF6F00),
    secondaryColor: Color(0xFFFF4081),
    borderColor: Color(0xFFF57C00),
    gridColor: Color(0xFFE65100),
    bgColor: Color(0xFFFFF8E1),
    boardBgColor: Color(0xFFFFECB3),
    blackStoneGrad1: [Color(0xFFBF360C), Color(0xFFE65100)],
    blackStoneGrad2: [Color(0xFFFF6F00), Color(0xFFFF8F00)],
    whiteStoneGrad1: [Color(0xFFFFE0B2), Color(0xFFFF8F00)],
    whiteStoneGrad2: [Color(0xFFFFF8E1), Color(0xFFFFE0B2)],
    textColor: Color(0xFFE65100),
  );

  /// 水墨丹青 — 中国书画风
  static const inkWashPainting = ThemePalette._private(
    name: '水墨丹青',
    primaryColor: Color(0xFF37474F),
    secondaryColor: Color(0xFFBF360C),
    borderColor: Color(0xFF5D4037),
    gridColor: Color(0xFF4E342E),
    bgColor: Color(0xFFF5F5F5),
    boardBgColor: Color(0xFFEFEBE9),
    blackStoneGrad1: [Color(0xFF37474F), Color(0xFF263238)],
    blackStoneGrad2: [Color(0xFF455A64), Color(0xFF37474F)],
    whiteStoneGrad1: [Color(0xFFFFFDF0), Color(0xFFFFF8E1)],
    whiteStoneGrad2: [Color(0xFFFFFBE0), Color(0xFFFFF8E1)],
    textColor: Color(0xFF37474F),
  );

  /// 所有主题列表，按索引供 UI 选择器使用
  static const List<ThemePalette> all = [
    classicBlackWhite,
    cosmicBlueRed,
    emeraldGold,
    neonPurpleCyan,
    sunsetOrangePink,
    inkWashPainting,
  ];

  // 内部私有构造函数，允许 const 实例化
  const ThemePalette._private({
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.borderColor,
    required this.gridColor,
    required this.bgColor,
    required this.boardBgColor,
    required this.blackStoneGrad1,
    required this.blackStoneGrad2,
    required this.whiteStoneGrad1,
    required this.whiteStoneGrad2,
    required this.textColor,
  });
}
