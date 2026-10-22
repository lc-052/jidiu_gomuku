import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'models/game_mode.dart';
import 'models/game_kind.dart';
import 'models/theme_notifier.dart';
export 'models/theme_notifier.dart';
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
  final themeNotifier = ThemeNotifier();

  runApp(GomukuApp(themeNotifier: themeNotifier));
}

/// 寄丢五子棋 - 主应用入口
class GomukuApp extends StatelessWidget {
  final ThemeNotifier themeNotifier;

  const GomukuApp({super.key, required this.themeNotifier});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: themeNotifier,
      child: Consumer<ThemeNotifier>(
        builder: (context, themeNotifier, _) {
          return MaterialApp.router(
            title: '寄丢棋室',
            debugShowCheckedModeBanner: false,
            theme: themeNotifier.theme(Brightness.light),
            darkTheme: themeNotifier.theme(Brightness.dark),
            themeMode: themeNotifier.themeMode,
            routerConfig: router,
          );
        },
      ),
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
          kind: extra?['kind'] as GameKind? ?? GameKind.gomoku,
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
      builder: (context, state) => OnlineLobbyScreen(
          kind: (state.extra as Map<String, dynamic>?)?['kind'] as GameKind? ??
              GameKind.gomoku),
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
