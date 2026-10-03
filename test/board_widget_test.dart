import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/widgets/board_widget.dart';

void main() {
  // 构造一个只有 (7,7) 黑子与 (3,3) 白子的棋盘
  List<List<CellState>> sampleBoard() {
    final b = List.generate(15, (_) => List.filled(15, CellState.empty));
    b[7][7] = CellState.black;
    b[3][3] = CellState.white;
    return b;
  }

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 300, height: 420, child: child),
          ),
        ),
      );

  testWidgets('含棋子的棋盘渲染不抛出绘制异常（6 套主题逐一验证）', (tester) async {
    for (int theme = 0; theme < 6; theme++) {
      await tester.pumpWidget(wrap(BoardWidget(
        board: sampleBoard(),
        gameState: GameState.playing,
        currentPlayer: Player.black,
        lastMove: const Position(row: 7, col: 7),
        themeIndex: theme,
        onTapCell: (r, c) {},
      )));
      expect(tester.takeException(), isNull, reason: '主题 $theme 渲染棋子时抛异常');
    }
  });

  testWidgets('棋盘保持正方形（紧约束下不被拉伸）', (tester) async {
    await tester.pumpWidget(wrap(BoardWidget(
      board: sampleBoard(),
      gameState: GameState.playing,
      currentPlayer: Player.black,
      themeIndex: 0,
      onTapCell: (r, c) {},
    )));

    // LayoutBuilder 根尺寸 300x420，棋盘本体（Container）应取 min 后居中为正方形
    final size = tester.getSize(
      find.descendant(
        of: find.byType(BoardWidget),
        matching: find.byType(Container),
      ),
    );
    expect(size.width, size.height);
    expect(size.width, lessThan(300)); // 留了 8px 边框余量
  });

  testWidgets('点击画布中心映射到天元 (7,7)', (tester) async {
    Position? tapped;
    await tester.pumpWidget(wrap(BoardWidget(
      board: sampleBoard(),
      gameState: GameState.playing,
      currentPlayer: Player.black,
      themeIndex: 0,
      onTapCell: (r, c) => tapped = Position(row: r, col: c),
    )));

    await tester.tapAt(tester.getCenter(find.byType(BoardWidget)));
    await tester.pump();
    expect(tapped, const Position(row: 7, col: 7));
  });
}
