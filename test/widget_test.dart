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
import 'package:gomuku/models/game_state.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });
  Widget wrap(Widget child) => ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: Builder(
          builder: (context) => MaterialApp(
              theme: context.watch<ThemeNotifier>().theme(Brightness.light),
              darkTheme: context.watch<ThemeNotifier>().theme(Brightness.dark),
              themeMode: context.watch<ThemeNotifier>().themeMode,
              home: child)));
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
