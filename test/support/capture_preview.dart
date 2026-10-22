// Run: flutter test test/support/capture_preview.dart --dart-define=PREVIEW_FONT=C:/Windows/Fonts/msyh.ttc
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gomuku/models/theme_notifier.dart';
import 'package:gomuku/models/game_kind.dart';
import 'package:gomuku/screens/main_menu_screen.dart';
import 'package:gomuku/screens/game_screen.dart';
import 'package:gomuku/screens/settings_screen.dart';
import 'package:gomuku/services/storage_service.dart';
import 'package:gomuku/widgets/board_widget.dart';

void main() {
  testWidgets('capture representative layouts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    const iconFont = String.fromEnvironment('PREVIEW_ICONS');
    if (iconFont.isNotEmpty) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(
            ByteData.sublistView(File(iconFont).readAsBytesSync())));
      await icons.load();
    }
    const font = String.fromEnvironment('PREVIEW_FONT');
    if (font.isNotEmpty) {
      final loader = FontLoader('PreviewSans')
        ..addFont(
            Future.value(ByteData.sublistView(File(font).readAsBytesSync())));
      await loader.load();
    }
    final key = GlobalKey();
    final theme = ThemeNotifier()..setThemeMode(ThemeMode.light);
    Widget wrap(Widget child) => ChangeNotifierProvider.value(
        value: theme,
        child: Builder(builder: (context) {
          final n = context.watch<ThemeNotifier>();
          return RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: n.theme(Brightness.light).copyWith(
                    textTheme: n.theme(Brightness.light).textTheme.apply(
                        fontFamily: font.isEmpty ? null : 'PreviewSans')),
                darkTheme: n.theme(Brightness.dark).copyWith(
                    textTheme: n.theme(Brightness.dark).textTheme.apply(
                        fontFamily: font.isEmpty ? null : 'PreviewSans')),
                themeMode: n.themeMode,
                home: child,
              ));
        }));
    Future<void> capture(String name) async {
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/icon/app_icon.png'), key.currentContext!));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final picture = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/previews/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(wrap(const MainMenuScreen()));
    await capture('home-light');
    for (int i = 1; i < 5; i++) {
      theme.setThemeIndex(i);
      await capture('home-theme-$i');
    }
    theme.setThemeIndex(0);
    await StorageService().savePreferredColor('black');
    await tester.pumpWidget(wrap(const GameScreen(
        key: ValueKey('go-ai'), gameMode: 1, kind: GameKind.go)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对弈'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(BoardWidget)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    expect(find.textContaining('已行 2 手'), findsOneWidget);
    await capture('go-ai-light');
    await tester
        .pumpWidget(wrap(const GameScreen(gameMode: 0, kind: GameKind.go)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对弈'));
    await capture('go-light');
    theme.setThemeMode(ThemeMode.dark);
    await capture('go-dark');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(wrap(const SettingsScreen()));
    await capture('settings-dark-mobile');
    theme.setThemeMode(ThemeMode.light);
    await tester.pumpWidget(wrap(const MainMenuScreen()));
    await capture('home-light-mobile');
    await tester.pumpWidget(const SizedBox.shrink());
    theme.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
