import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/models/theme_model.dart';

/// 棋盘绘制组件 —— 在指定大小的画布上渲染木纹底、网格线、黑白棋子与最后一步标记。
/// 坐标系：n 条线产生 n 个交点，交点间距 cellSize，网格整体在画布中居中，
/// 四周留出一半格子的边距，保证边缘棋子完整显示。
class BoardWidget extends StatelessWidget {
  final List<List<CellState>> board;
  final GameState gameState;
  final Position? lastMove;
  final Player currentPlayer;
  final void Function(int row, int col) onTapCell;
  final int themeIndex;

  const BoardWidget({
    super.key,
    required this.board,
    required this.gameState,
    required this.currentPlayer,
    required this.onTapCell,
    this.lastMove,
    this.themeIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ThemePalette.all[themeIndex];
    final n = board.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        if (side <= 0 || n < 2) return const SizedBox.shrink();

        // 留出细边框余量后，按“n 格宽 = (n-1) 段网格 + 每侧半格边距”规划：
        // totalSize = cellSize * n，网格跨度 = cellSize * (n - 1)，origin = cellSize / 2
        final totalSize = side - 8;
        final cellSize = totalSize / n;
        final gridSpan = cellSize * (n - 1);
        final origin = cellSize / 2;
        final stoneRadius = cellSize * 0.44;

        // Center 提供松约束：父级（Expanded/Padding）的紧约束不会把
        // 棋盘拉成非正方形，保证 Container 与 CustomPaint 都是 totalSize 见方
        return Center(
          child: Container(
            width: totalSize,
            height: totalSize,
            decoration: BoxDecoration(
              color: palette.boardBgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: palette.borderColor.withValues(alpha: 0.6),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: GestureDetector(
              onTapDown: (details) {
                final dx = details.localPosition.dx;
                final dy = details.localPosition.dy;
                // 交点坐标 = origin + i * cellSize，取最近交点
                final col = ((dx - origin) / cellSize).round();
                final row = ((dy - origin) / cellSize).round();
                if (row >= 0 && row < n && col >= 0 && col < n) {
                  onTapCell(row, col);
                }
              },
              child: CustomPaint(
                size: Size(totalSize, totalSize),
                painter: _BoardPainter(
                  board: board,
                  gameState: gameState,
                  lastMove: lastMove,
                  palette: palette,
                  cellSize: cellSize,
                  gridSpan: gridSpan,
                  origin: origin,
                  stoneRadius: stoneRadius,
                  n: n,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ========== Painter ==========

class _BoardPainter extends CustomPainter {
  final List<List<CellState>> board;
  final GameState gameState;
  final Position? lastMove;
  final ThemePalette palette;
  final double cellSize;
  final double gridSpan;
  final double origin;
  final double stoneRadius;
  final int n;

  _BoardPainter({
    required this.board,
    required this.gameState,
    required this.lastMove,
    required this.palette,
    required this.cellSize,
    required this.gridSpan,
    required this.origin,
    required this.stoneRadius,
    required this.n,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ---------- 网格线 ----------
    final gp = Paint()
      ..color = palette.gridColor
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < n; i++) {
      final pos = origin + i * cellSize;
      // 水平线
      canvas.drawLine(Offset(origin, pos), Offset(origin + gridSpan, pos), gp);
      // 垂直线
      canvas.drawLine(Offset(pos, origin), Offset(pos, origin + gridSpan), gp);
    }

    // ---------- 星位点（天元 + 四角星）----------
    final sp = Paint()
      ..color = palette.gridColor
      ..style = PaintingStyle.fill;
    final sr = cellSize * 0.07;
    void drawDot(int r, int c) {
      canvas.drawCircle(
          Offset(origin + c * cellSize, origin + r * cellSize), sr, sp);
    }

    if (n == 15) {
      drawDot(3, 3);
      drawDot(3, 11);
      drawDot(7, 7);
      drawDot(11, 3);
      drawDot(11, 11);
    } else if (n >= 9) {
      drawDot(n ~/ 2, n ~/ 2);
    }

    // ---------- 棋子 ----------
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        final cell = board[r][c];
        if (cell == CellState.empty) continue;

        // 棋子置于网格线交点
        final cx = origin + c * cellSize;
        final cy = origin + r * cellSize;

        if (cell == CellState.black) {
          // 黑子：深色径向渐变（不传 stops，均匀分布，
          // 避免与调色板颜色数量不一致导致 createShader 断言失败）
          final grad = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            radius: 1.2,
            colors: palette.blackStoneGrad1,
          );
          final p = Paint()
            ..shader = grad.createShader(
                Rect.fromCircle(center: Offset(cx, cy), radius: stoneRadius));
          canvas.drawCircle(Offset(cx, cy), stoneRadius, p);

          // 高光
          canvas.drawCircle(
              Offset(cx - stoneRadius * 0.3, cy - stoneRadius * 0.3),
              stoneRadius * 0.18,
              Paint()..color = Colors.white.withValues(alpha: 0.12));
        } else {
          // 白子：亮色径向渐变 + 细边（同上，不传 stops）
          final grad = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            radius: 1.2,
            colors: palette.whiteStoneGrad1,
          );
          canvas.drawCircle(
              Offset(cx, cy),
              stoneRadius,
              Paint()
                ..shader = grad.createShader(Rect.fromCircle(
                    center: Offset(cx, cy), radius: stoneRadius)));
          canvas.drawCircle(
              Offset(cx, cy),
              stoneRadius,
              Paint()
                ..color = Colors.grey.withValues(alpha: 0.3)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.8);
          canvas.drawCircle(
              Offset(cx - stoneRadius * 0.3, cy - stoneRadius * 0.3),
              stoneRadius * 0.18,
              Paint()..color = Colors.white.withValues(alpha: 0.6));
        }

        // ---------- 最后一步红色标记 ----------
        if (lastMove != null && lastMove!.row == r && lastMove!.col == c) {
          canvas.drawCircle(
            Offset(cx, cy),
            stoneRadius * 0.2,
            Paint()
              ..color = const Color(0xFFFF2222)
              ..style = PaintingStyle.fill,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}
