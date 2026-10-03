import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'models/game_mode.dart';
import 'models/theme_model.dart';
import 'services/network_service.dart';
import 'services/storage_service.dart';
import 'screens/main_menu_screen.dart';
import 'screens/game_screen.dart';
import 'screens/online_lobby_screen.dart';
import 'screens/online_game_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();

  // 主题通知器提前构建并从持久化存储中恢复上次选择，供 Provider 与路由共享
  final themeNotifier = ThemeNotifier()
    ..setThemeIndex(StorageService().themeIndex);

  runApp(GomukuApp(themeNotifier: themeNotifier));
}

/// 寄丢五子棋 - 主应用入口
class GomukuApp extends StatelessWidget {
  final ThemeNotifier themeNotifier;

  const GomukuApp({super.key, required this.themeNotifier});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeNotifier),
        ChangeNotifierProvider(create: (_) => GameModeNotifier()),
      ],
      child: Consumer<ThemeNotifier>(
        builder: (context, themeNotifier, _) {
          final appTheme = _buildMaterialTheme(themeNotifier);
          return MaterialApp.router(
            title: '寄丢五子棋',
            debugShowCheckedModeBanner: false,
            theme: appTheme,
            darkTheme: appTheme,
            themeMode: ThemeMode.light,
            routerConfig: router,
          );
        },
      ),
    );
  }

  /// 根据所选主题构建 Material 3 主题
  ThemeData _buildMaterialTheme(ThemeNotifier notifier) {
    final palette = ThemePalette.all[notifier.chosenThemeIndex];
    return ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primaryColor,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      fontFamily: 'PingFang SC',
    );
  }
}

// ========== GoRouter 路由配置 ==========

final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: [
    /// 主菜单页面（根路由）
    GoRoute(
      path: '/',
      name: 'main-menu',
      builder: (context, state) => const MainMenuScreen(),
    ),

    /// 本地游戏页面
    GoRoute(
      path: '/game',
      name: 'game',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final modeRaw = extra?['gameMode'];
        GameMode gameMode;
        if (modeRaw is GameMode) {
          gameMode = modeRaw;
        } else if (modeRaw == 'ai') {
          gameMode = GameMode.ai;
        } else {
          gameMode = GameMode.local;
        }
        return GameScreen(
          gameMode: gameMode == GameMode.ai ? 1 : 0,
          chosenThemeIndex:
              extra?['chosenThemeIndex'] as int? ?? StorageService().themeIndex,
        );
      },
    ),

    /// 在线匹配大厅
    GoRoute(
      path: '/online',
      name: 'online-lobby',
      builder: (context, state) => const OnlineLobbyScreen(),
    ),

    /// 在线对战场面
    GoRoute(
      path: '/online-game',
      name: 'online-game',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return OnlineGameScreen(
          network: extra?['network'] as NetworkService?,
          roomId: extra?['roomId'] as String?,
          playerColor: extra?['playerColor'] as String? ?? 'black',
        );
      },
    ),

    /// 设置页面
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

// ========== 状态通知器 ==========

/// 主题选择器，管理当前所选主题的索引
class ThemeNotifier extends ChangeNotifier {
  int _chosenThemeIndex = 0;

  int get chosenThemeIndex => _chosenThemeIndex;

  /// 切换主题索引
  void setThemeIndex(int index) {
    if (index >= 0 && index < ThemePalette.all.length) {
      _chosenThemeIndex = index;
      notifyListeners();
    }
  }
}

/// 游戏模式选择器，管理当前选择的游戏模式
class GameModeNotifier extends ChangeNotifier {
  GameMode _selectedMode = GameMode.local;

  GameMode get selectedMode => _selectedMode;

  /// 设置游戏模式
  void setMode(GameMode mode) {
    _selectedMode = mode;
    notifyListeners();
  }
}
