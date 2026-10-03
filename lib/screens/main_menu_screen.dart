import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:gomuku/main.dart';
import 'package:gomuku/models/theme_model.dart';
import 'package:gomuku/services/storage_service.dart';

/// 主菜单界面 —— 用户启动应用后看到的第一屏。
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  // 注意：这里必须用 push 而不是 go —— go() 会替换整个导航栈，
  // 对局页成为栈底后 pop「退出对局」会弹空导致黑屏。
  void _navigateToLocal() {
    GoRouter.of(context).push('/game', extra: {
      'gameMode': 'local',
      'chosenThemeIndex': context.read<ThemeNotifier>().chosenThemeIndex,
    });
  }

  void _navigateToAI() {
    GoRouter.of(context).push('/game', extra: {
      'gameMode': 'ai',
      'chosenThemeIndex': context.read<ThemeNotifier>().chosenThemeIndex,
    });
  }

  void _navigateToOnline() {
    GoRouter.of(context).push('/online');
  }

  void _navigateToSettings() {
    GoRouter.of(context).push('/settings');
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeIndex = context.watch<ThemeNotifier>().chosenThemeIndex;
    final palette = ThemePalette.all[themeIndex];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.bgColor,
              palette.boardBgColor,
              palette.bgColor,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ========== 顶部标题区域 ==========
              Flexible(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (context, child) {
                        final t = CurvedAnimation(
                          parent: _animController,
                          curve: Curves.easeOutBack,
                        ).value;
                        return Transform.translate(
                          offset: Offset(0, 20 * (1 - t)),
                          child: Opacity(
                            opacity: t,
                            child: Column(
                              children: [
                                Icon(
                                  Icons.sports_golf_rounded,
                                  size: 72,
                                  color: palette.primaryColor,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '寄丢五子棋',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: palette.primaryColor,
                                    letterSpacing: 4,
                                    shadows: [
                                      Shadow(
                                        color: palette.primaryColor
                                            .withValues(alpha: 0.3),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '—— 落子无悔，智者博弈 ——',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: palette.secondaryColor,
                                    fontStyle: FontStyle.italic,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ========== 模式选择卡片 ==========
              Flexible(
                flex: 5,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModeCard(
                        context: context,
                        icon: Icons.people_outline_rounded,
                        title: '双人对战',
                        subtitle: '同一设备，两人轮流下棋',
                        delay: 0,
                        onTap: _navigateToLocal,
                        themeIndex: themeIndex,
                        animController: _animController,
                      ),
                      const SizedBox(height: 16),
                      _buildModeCard(
                        context: context,
                        icon: Icons.lightbulb_outline_rounded,
                        title: '人机对战',
                        subtitle: '与电脑智多星切磋棋艺',
                        delay: 0.15,
                        onTap: _navigateToAI,
                        themeIndex: themeIndex,
                        animController: _animController,
                      ),
                      const SizedBox(height: 16),
                      _buildModeCard(
                        context: context,
                        icon: Icons.public_outlined,
                        title: '在线联机',
                        subtitle: '与世界各地的棋友对弈',
                        delay: 0.3,
                        onTap: _navigateToOnline,
                        themeIndex: themeIndex,
                        animController: _animController,
                      ),
                    ],
                  ),
                ),
              ),

              // ========== 底部设置区域 ==========
              Flexible(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // 主题选择器
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        ThemePalette.all.length,
                        (index) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: GestureDetector(
                            onTap: () {
                              context
                                  .read<ThemeNotifier>()
                                  .setThemeIndex(index);
                              StorageService().saveThemeIndex(index);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ThemePalette.all[index].primaryColor,
                                border: Border.all(
                                  color: themeIndex == index
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: themeIndex == index
                                    ? [
                                        BoxShadow(
                                          color: ThemePalette
                                              .all[index].primaryColor
                                              .withValues(alpha: 0.5),
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ThemePalette.all[themeIndex].name,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.secondaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 设置按钮
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _navigateToSettings,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color:
                                  palette.primaryColor.withValues(alpha: 0.3),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.settings_outlined,
                                size: 20,
                                color: palette.primaryColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '游戏设置',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: palette.primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required double delay,
    required VoidCallback onTap,
    required int themeIndex,
    required AnimationController animController,
  }) {
    final palette = ThemePalette.all[themeIndex];
    return AnimatedBuilder(
      animation: animController,
      builder: (context, child) {
        final progress = animController.value;
        final effectiveDelay = delay * 0.8;
        final t = progress > effectiveDelay
            ? ((progress - effectiveDelay) / (1 - effectiveDelay))
                .clamp(0.0, 1.0)
            : 0.0;
        final eased = Curves.easeOutCubic.transform(t);

        return Transform.translate(
          offset: Offset(0, 40 * (1 - eased)),
          child: Opacity(
            opacity: eased,
            child: _ModeCard(
              icon: icon,
              title: title,
              subtitle: subtitle,
              primaryColor: palette.primaryColor,
              secondaryColor: palette.secondaryColor,
              onTap: onTap,
            ),
          ),
        );
      },
    );
  }
}

// ========== 单个模式卡片组件 ==========

class _ModeCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color primaryColor;
  final Color secondaryColor;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryColor,
    required this.secondaryColor,
    required this.onTap,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> with TickerProviderStateMixin {
  late AnimationController _rippleController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() => _isPressed = true);
    _rippleController.forward().then((_) {
      setState(() => _isPressed = false);
      widget.onTap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.25),
              Colors.white.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.primaryColor.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.primaryColor.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _handleTap,
          splashColor: widget.primaryColor.withValues(alpha: 0.2),
          highlightColor: widget.primaryColor.withValues(alpha: 0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                // 图标区
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  transform: Matrix4.identity()
                    ..scaleByDouble(
                      _isPressed ? 0.9 : 1.0,
                      _isPressed ? 0.9 : 1.0,
                      1.0,
                      1.0,
                    ),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.primaryColor.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 28,
                      color: widget.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // 文字区
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: widget.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // 右箭头
                Icon(
                  Icons.chevron_right_rounded,
                  size: 24,
                  color: widget.secondaryColor.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
