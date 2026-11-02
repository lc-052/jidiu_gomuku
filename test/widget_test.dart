import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gomuku/models/game_kind.dart';
import 'package:gomuku/models/theme_notifier.dart';
import 'package:gomuku/screens/main_menu_screen.dart';
import 'package:gomuku/screens/game_screen.dart';
import 'package:gomuku/screens/settings_screen.dart';
import 'package:gomuku/screens/online_lobby_screen.dart';
import 'package:gomuku/screens/online_game_screen.dart';
import 'package:gomuku/services/storage_service.dart';
import 'package:gomuku/widgets/board_widget.dart';
import 'package:gomuku/widgets/game_cards.dart';
import 'package:gomuku/models/game_state.dart';

Widget wrap(Widget child) => ChangeNotifierProvider(
    create: (_) => ThemeNotifier(),
    child: Builder(
        builder: (context) => MaterialApp(
            theme: context.watch<ThemeNotifier>().theme(Brightness.light),
            darkTheme: context.watch<ThemeNotifier>().theme(Brightness.dark),
            themeMode: context.watch<ThemeNotifier>().themeMode,
            home: child)));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });
  setUp(() async {
    await StorageService().saveShowMoveNumbers(false);
    await StorageService().saveAiDelayMs(500);
    await StorageService().saveDifficultyIndex(1);
    await StorageService().savePreferredColor('black');
  });
  testWidgets(
      'setup selects AI difficulty and delay for either game on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final kind in GameKind.values) {
      await StorageService().saveAiDelayMs(500);
      await tester.pumpWidget(
          wrap(GameScreen(key: ValueKey(kind), gameMode: 1, kind: kind)));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '0.5 秒'))
              .selected,
          true);
      final hardChoice = find.widgetWithText(ChoiceChip, '困难');
      await tester.ensureVisible(hardChoice);
      await tester.pumpAndSettle();
      await tester.tap(hardChoice);
      await tester.pumpAndSettle();
      final delayChoice = find.widgetWithText(ChoiceChip, '1.5 秒');
      await tester.ensureVisible(delayChoice);
      await tester.pumpAndSettle();
      await tester.tap(delayChoice);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始对弈'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始对弈'));
      await tester.pumpAndSettle();
      final s = tester
          .widget<PlayerStatusCard>(find.byType(PlayerStatusCard))
          .session;
      expect(s.difficulty, Difficulty.hard);
      expect(s.aiDelay, const Duration(milliseconds: 1500));
      expect(StorageService().aiDelayMs, 1500);
      expect(StorageService().difficultyIndex, Difficulty.hard.index);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets(
      'stone numbers can be toggled during either local game without changing play',
      (tester) async {
    for (final kind in GameKind.values) {
      await StorageService().saveShowMoveNumbers(false);
      await tester.pumpWidget(
          wrap(GameScreen(key: ValueKey(kind), gameMode: 0, kind: kind)));
      await tester.tap(find.text('显示棋子手数'));
      await tester.ensureVisible(find.text('开始对弈'));
      await tester.tap(find.text('开始对弈'));
      await tester.pumpAndSettle();
      tester.widget<BoardWidget>(find.byType(BoardWidget)).onTapCell(0, 0);
      await tester.pump();
      tester.widget<BoardWidget>(find.byType(BoardWidget)).onTapCell(8, 8);
      await tester.pump();
      final numbers = {
        const Position(row: 0, col: 0): 1,
        const Position(row: 8, col: 8): 2
      };
      expect(tester.widget<BoardWidget>(find.byType(BoardWidget)).moveNumbers,
          numbers);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      var board = tester.widget<BoardWidget>(find.byType(BoardWidget));
      expect(board.moveNumbers, isEmpty);
      expect(board.board[8][8], CellState.white);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<BoardWidget>(find.byType(BoardWidget)).moveNumbers,
          numbers);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets('home, settings, and both games fit phone and desktop layouts',
      (tester) async {
    for (final size in [const Size(360, 800), const Size(1280, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final screen in [
        const MainMenuScreen(),
        const SettingsScreen(),
        const GameScreen(gameMode: 0),
        const GameScreen(gameMode: 0, kind: GameKind.go),
        const OnlineLobbyScreen(),
        const OnlineGameScreen()
      ]) {
        await tester.pumpWidget(wrap(screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (screen is GameScreen) {
          await tester.ensureVisible(find.text('开始对弈'));
          await tester.tap(find.text('开始对弈'));
          await tester.pumpAndSettle();
          expect(find.text('轮到黑方落子'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('local victory shows result and keeps winning stones for review',
      (tester) async {
    await tester.pumpWidget(wrap(const GameScreen(gameMode: 0)));
    await tester.tap(find.text('开始对弈'));
    await tester.pumpAndSettle();
    for (var col = 0; col < 5; col++) {
      tester.widget<BoardWidget>(find.byType(BoardWidget)).onTapCell(4, col);
      await tester.pump();
      if (col < 4) {
        tester.widget<BoardWidget>(find.byType(BoardWidget)).onTapCell(5, col);
        await tester.pump();
      }
    }
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('黑方获胜')),
        findsOneWidget);
    await tester.tap(find.text('查看棋盘'));
    await tester.pumpAndSettle();
    final board = tester.widget<BoardWidget>(find.byType(BoardWidget));
    expect(board.board[4][4], CellState.black);
    expect(board.winningPositions.length, 5);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Go count button marks territory, clears dead stones and resumes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(wrap(const GameScreen(gameMode: 0, kind: GameKind.go)));
    await tester.tap(find.widgetWithText(ChoiceChip, '6.5 目'));
    await tester.tap(find.text('开始对弈'));
    await tester.pumpAndSettle();
    for (final p in [(0, 1), (8, 8), (1, 0)]) {
      tester
          .widget<BoardWidget>(find.byType(BoardWidget))
          .onTapCell(p.$1, p.$2);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('数子'));
    await tester.tap(find.text('数子'));
    await tester.pumpAndSettle();
    expect(find.text('数子 · 核对死子'), findsOneWidget);
    var board = tester.widget<BoardWidget>(find.byType(BoardWidget));
    expect(board.blackTerritory, {const Position(row: 0, col: 0)});
    expect(find.textContaining('贴目 6.5'), findsOneWidget);
    board.onTapCell(0, 1);
    await tester.pump();
    expect(
        tester
            .widget<BoardWidget>(find.byType(BoardWidget))
            .markedPositions
            .length,
        1);
    await tester.ensureVisible(find.text('清除死子标记'));
    await tester.tap(find.text('清除死子标记'));
    await tester.pump();
    expect(tester.widget<BoardWidget>(find.byType(BoardWidget)).markedPositions,
        isEmpty);
    await tester.tap(find.text('继续下棋'));
    await tester.pumpAndSettle();
    expect(find.text('轮到白方落子'), findsOneWidget);
    board = tester.widget<BoardWidget>(find.byType(BoardWidget));
    expect(board.blackTerritory, isEmpty);
    board.onTapCell(4, 4);
    await tester.pump();
    expect(tester.widget<BoardWidget>(find.byType(BoardWidget)).board[4][4],
        CellState.white);
    await tester.ensureVisible(find.text('数子'));
    await tester.tap(find.text('数子'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('双方确认，结算'));
    await tester.tap(find.text('双方确认，结算'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('display modes update settings immediately', (tester) async {
    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.tap(find.widgetWithText(ChoiceChip, '深色'));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(SettingsScreen));
    expect(Theme.of(ctx).brightness, Brightness.dark);
    await tester.tap(find.widgetWithText(ChoiceChip, '浅色'));
    await tester.pumpAndSettle();
    expect(Theme.of(ctx).brightness, Brightness.light);
    await tester.tap(find.widgetWithText(ChoiceChip, '跟随系统'));
    await tester.pumpAndSettle();
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(Theme.of(ctx).brightness, Brightness.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(ctx).brightness, Brightness.light);
    expect(tester.takeException(), isNull);
  });
}
