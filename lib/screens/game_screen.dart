import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/models/theme_model.dart';
import 'package:gomuku/services/storage_service.dart';
import 'package:gomuku/services/ai_service.dart';
import 'package:gomuku/services/game_engine.dart';
import 'package:gomuku/widgets/board_widget.dart';

/// 游戏界面 —— 本地双人对战与人机对战的核心玩法页。
class GameScreen extends StatefulWidget {
  /// 游戏模式：0 = 本地双人, 1 = AI 人机
  final int gameMode;
  final int chosenThemeIndex;

  const GameScreen({
    super.key,
    required this.gameMode,
    this.chosenThemeIndex = 0,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameEngine _engine;
  Position? _lastMove;
  bool _showGameOver = false;
  bool _resigned = false; // 投降判负时引擎仍是 playing，用它统一表示“本局已结束”
  String _winnerText = '';
  Timer? _aiTimer;
  int _whiteStoneCount = 0;
  int _blackStoneCount = 0;

  /// 本局是否已结束（五连/平局由引擎判断，投降由 _resigned 标记）
  bool get _gameOver => _resigned || _engine.gameState != GameState.playing;

  // ========== Lifecycle ==========

  @override
  void initState() {
    super.initState();
    _engine = GameEngine(boardSize: BoardSize.standard);
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    super.dispose();
  }

  // ========== 计算棋子数量 ==========

  int _countStones(CellState state) {
    int count = 0;
    for (final row in _engine.board) {
      for (final cell in row) {
        if (cell == state) count++;
      }
    }
    return count;
  }

  void _updateCounts() {
    setState(() {
      _blackStoneCount = _countStones(CellState.black);
      _whiteStoneCount = _countStones(CellState.white);
    });
  }

  // ========== 落子逻辑 ==========

  Future<void> _onCellTapped(int row, int col) async {
    // 游戏已结束或轮到对手（AI/对方玩家）时不允许点击
    if (_showGameOver || _gameOver) return;
    if (widget.gameMode == 1 && _engine.currentPlayer != Player.black) return;

    if (_engine.makeMove(row, col)) {
      final storage = StorageService();
      if (storage.vibrationEnabled) {
        // Vibration requires additional platform channel package - silent OK
      }

      _lastMove = Position(row: row, col: col);
      _updateCounts();

      // 检查胜负
      if (_checkResult()) return;

      // AI 自动回应
      if (widget.gameMode == 1) {
        _scheduleAiMove();
      }
    }
  }

  void _scheduleAiMove() {
    _aiTimer?.cancel();
    _aiTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _engine.gameState != GameState.playing) return;
      if (_engine.currentPlayer != Player.white) return;

      final ai = AIService(
        boardSize: _engine.boardSize,
        difficulty:
            Difficulty.values[StorageService().difficultyIndex.clamp(0, 2)],
        aiPlayer: Player.white,
      );
      final bestMove = ai.getBestMove(_engine, Player.white);

      if (bestMove != null && mounted) {
        final moved = _engine.makeMove(bestMove.row, bestMove.col);
        if (moved) {
          _lastMove = bestMove;
          _updateCounts();
          _checkResult();
        }
      }
    });
  }

  // ========== 结果检查 ==========

  bool _checkResult() {
    switch (_engine.gameState) {
      case GameState.blackWon:
        _winnerText = widget.gameMode == 1 ? '你赢了！黑方五连获胜，恭喜！' : '黑方五连获胜，恭喜黑方！';
        setState(() => _showGameOver = true);
        return true;
      case GameState.whiteWon:
        _winnerText = widget.gameMode == 1 ? '电脑五连获胜，再接再厉！' : '白方五连获胜，恭喜白方！';
        setState(() => _showGameOver = true);
        return true;
      case GameState.draw:
        _winnerText = '棋盘已满，本局平局！';
        setState(() => _showGameOver = true);
        return true;
      default:
        return false;
    }
  }

  // ========== UI Builders ==========

  @override
  Widget build(BuildContext context) {
    final palette = ThemePalette.all[widget.chosenThemeIndex];
    final modeLabel = widget.gameMode == 0 ? '双人对战' : '人机对战';

    return PopScope(
      // 只有“已结束且真的可弹出”才放行系统返回；
      // 栈底时 canPop=false，交给 onPopInvoked 兜底回主菜单，避免黑屏
      canPop: _engine.gameState != GameState.playing &&
          Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // 已结束但无法 pop（本页在栈底）：直接回主菜单
        if (_engine.gameState != GameState.playing) {
          _exitGame();
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('退出对局'),
            content: const Text('确定要放弃本局棋吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('继续下棋'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.primaryColor,
                ),
                child: const Text('放弃退出'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          _exitGame();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                palette.bgColor,
                palette.boardBgColor,
              ],
            ),
          ),
          // 渐变背景铺满全屏；内容用 SafeArea 避开状态栏/刘海与底部手势条
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    // ========== 顶部状态栏 ==========
                    _buildTopBar(context, palette, modeLabel),

                    // ========== 棋盘区域 ==========
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          // Stone count
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '黑子: $_blackStoneCount 枚  |  白子: $_whiteStoneCount 枚',
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.secondaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                          // Board
                          Expanded(
                            flex: 6,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: BoardWidget(
                                board: _engine.board,
                                gameState: _engine.gameState,
                                currentPlayer: _engine.currentPlayer,
                                lastMove: _lastMove,
                                themeIndex: widget.chosenThemeIndex,
                                onTapCell: _onCellTapped,
                              ),
                            ),
                          ),

                          // Mode indicator + current player info
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Chip(
                                  label: Text(modeLabel,
                                      style: const TextStyle(fontSize: 12)),
                                  backgroundColor: palette.primaryColor
                                      .withValues(alpha: 0.15),
                                  side: BorderSide(
                                      color: palette.primaryColor
                                          .withValues(alpha: 0.3)),
                                ),
                                const SizedBox(width: 8),
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor:
                                      _engine.currentPlayer.toColor(),
                                  child: _engine.currentPlayer == Player.black
                                      ? null
                                      : Icon(Icons.circle,
                                          size: 14, color: Colors.white),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '当前: ${_engine.currentPlayer == Player.black ? '黑方' : '白方'}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: palette.primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (widget.gameMode == 1 &&
                                    _engine.currentPlayer == Player.white) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          palette.primaryColor),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '思考中...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: palette.secondaryColor,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ========== 底部控制栏 ==========
                    _buildBottomBar(palette),
                  ],
                ),

                // ========== 对局结束遮罩 ==========
                if (_showGameOver)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.5),
                      child: _buildGameOverDialog(palette),
                    ),
                  ),

                // ========== 复盘横幅：结束但已关闭结算提示时 ==========
                if (_gameOver && !_showGameOver)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 96,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '本局已结束 · 复盘模式',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _showGameOver = true),
                              style: TextButton.styleFrom(
                                foregroundColor: palette.primaryColor,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: const Text('查看结算',
                                  style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========== Top Bar ==========

  Widget _buildTopBar(
      BuildContext context, ThemePalette palette, String modeLabel) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back_ios_rounded,
                size: 20, color: palette.textColor),
          ),
          // Current player indicator
          CircleAvatar(
            radius: 14,
            backgroundColor: _engine.currentPlayer.toColor(),
            child: _engine.currentPlayer == Player.black
                ? null
                : Icon(Icons.circle, size: 16, color: palette.bgColor),
          ),
          const SizedBox(width: 8),
          Text(
            widget.gameMode == 0 ? '黑方 vs 白方' : '执黑（你） vs 执白（AI）',
            style: TextStyle(
              fontSize: 14,
              color: palette.textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // 回合计时器（本局结束后冻结）
          if (_gameOver)
            Text(
              '已结束',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: palette.secondaryColor,
              ),
            )
          else
            _TimerDisplay(
                currentPlayer: _engine.currentPlayer, palette: palette),
        ],
      ),
    );
  }

  // ========== Bottom Bar ==========

  Widget _buildBottomBar(ThemePalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 悔棋
          _buildActionButton(
            icon: Icons.undo_rounded,
            label: '悔棋',
            onTap: _engine.moveHistory.isNotEmpty ? _undo : null,
            palette: palette,
          ),
          // 投降
          _buildActionButton(
            icon: Icons.flag_outlined,
            label: '投降',
            onTap:
                _engine.gameState == GameState.playing ? _confirmResign : null,
            palette: palette,
            danger: true,
          ),
          // 重新开始
          _buildActionButton(
            icon: Icons.refresh_rounded,
            label: '再来一局',
            onTap: _restart,
            palette: palette,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required ThemePalette palette,
    bool danger = false,
  }) {
    final effectiveColor = danger ? Colors.red.shade400 : palette.primaryColor;
    final isEnabled = onTap != null;

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.identity()
          ..scaleByDouble(
            isEnabled ? 1.0 : 0.95,
            isEnabled ? 1.0 : 0.95,
            1.0,
            1.0,
          ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isEnabled
                    ? effectiveColor.withValues(alpha: 0.12)
                    : Colors.grey.withValues(alpha: 0.1),
                border: Border.all(
                  color: isEnabled
                      ? effectiveColor.withValues(alpha: 0.3)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isEnabled ? effectiveColor : Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isEnabled ? effectiveColor : Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== Overlays ==========

  Widget _buildGameOverDialog(ThemePalette palette) {
    final isDraw = _engine.gameState == GameState.draw;

    return Center(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDraw ? Icons.handshake_outlined : Icons.emoji_events,
                size: 56,
                color: isDraw ? Colors.orange : palette.primaryColor,
              ),
              const SizedBox(height: 12),
              Text(
                '对局结束',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: palette.primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _winnerText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _exitGame,
                      child: const Text('退出对局'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _doReset,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.primaryColor,
                      ),
                      child: const Text('再来一局'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 关掉提示，留在页面上复盘最终盘面
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showGameOver = false),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('查看棋盘'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========== Actions ==========

  /// 退出对局：能弹回上一页（主菜单）就 pop；
  /// 万一本页在栈底（go/deep link 直达），改用 go('/') 回主菜单，避免弹空黑屏。
  void _exitGame() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      GoRouter.of(context).go('/');
    }
  }

  /// 清空棋盘并退出结算遮罩
  void _doReset() {
    _engine.reset();
    _lastMove = null;
    _winnerText = '';
    _showGameOver = false;
    _resigned = false;
    _blackStoneCount = 0;
    _whiteStoneCount = 0;
    setState(() {});
  }

  void _undo() {
    if (_engine.gameState != GameState.playing) return;
    if (_engine.moveHistory.length < 2) return;

    // In AI mode, undo both human and AI move
    if (widget.gameMode == 1 && _engine.moveHistory.length >= 2) {
      _engine.undoMove();
      _engine.undoMove();
    } else {
      _engine.undoMove();
    }

    // Update last move indicator
    if (_engine.moveHistory.isNotEmpty) {
      final lastRecord = _engine.moveHistory.last;
      _lastMove = lastRecord.position;
    } else {
      _lastMove = null;
    }
    _updateCounts();
  }

  void _confirmResign() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认投降'),
        content: const Text('投降后本局棋将结束，确定要放弃吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              // 投降：当前回合方判负，弹出结算
              if (widget.gameMode == 1) {
                setState(() {
                  _resigned = true;
                  _winnerText = '你已投降，电脑获胜。';
                  _showGameOver = true;
                });
              } else {
                final loser = _engine.currentPlayer;
                setState(() {
                  _resigned = true;
                  _winnerText = '${loser.cn}已投降，${loser.opponent().cn}获胜！';
                  _showGameOver = true;
                });
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('我认输了'),
          ),
        ],
      ),
    );
  }

  void _restart() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('再来一局'),
        content: const Text('确定要重新开始本局棋吗？当前进度将被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('暂不重开'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _doReset();
            },
            style: FilledButton.styleFrom(
              backgroundColor:
                  ThemePalette.all[widget.chosenThemeIndex].primaryColor,
            ),
            child: const Text('重新开始'),
          ),
        ],
      ),
    );
  }
}

// ========== 回合计时器组件 ==========

class _TimerDisplay extends StatefulWidget {
  final Player currentPlayer;
  final ThemePalette palette;

  const _TimerDisplay({
    required this.currentPlayer,
    required this.palette,
  });

  @override
  State<_TimerDisplay> createState() => _TimerDisplayState();
}

class _TimerDisplayState extends State<_TimerDisplay> {
  int _timeLeft = 30;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(_TimerDisplay old) {
    super.didUpdateWidget(old);
    if (old.currentPlayer != widget.currentPlayer) {
      _timeLeft = 30;
      _timer.cancel();
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _timeLeft--);
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeColor = _timeLeft <= 5
        ? Colors.red
        : _timeLeft <= 10
            ? Colors.orange
            : widget.palette.secondaryColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 16, color: timeColor),
        const SizedBox(width: 4),
        Text(
          '$_timeLeft',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: timeColor,
          ),
        ),
      ],
    );
  }
}
