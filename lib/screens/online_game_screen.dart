import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/models/theme_model.dart';
import 'package:gomuku/services/network_service.dart';
import 'package:gomuku/services/game_engine.dart';
import 'package:gomuku/widgets/board_widget.dart';
import 'package:gomuku/services/storage_service.dart';

/// Online multiplayer game screen with WebSocket sync.
/// 复用大厅传入的 NetworkService 实例（连接与房间状态由服务器驱动）。
class OnlineGameScreen extends StatefulWidget {
  final NetworkService? network;
  final String? roomId;
  final String playerColor;

  const OnlineGameScreen({
    super.key,
    this.network,
    this.roomId,
    this.playerColor = 'black',
  });

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  late final GameEngine _engine;
  late final NetworkService _network;
  bool _ownsNetwork = false;

  Position? _lastMove;
  bool _showGameOver = false;
  bool _ended = false; // 收到结算/投降后引擎可能仍是 playing，用它表示“本局已结束”
  String _winnerText = '';
  bool _gameStarted = false;
  bool _myReady = false;
  bool _oppReady = false;
  String _opponentName = '对手';
  bool _isMyTurn = false;
  String _connectivityStatus = 'connected';
  bool _chatVisible = false;
  final List<_ChatMessage> _chatHistory = [];
  final TextEditingController _chatController = TextEditingController();
  // 聊天面板未打开时的浮动消息气泡
  String? _chatBubbleText;
  Timer? _chatBubbleTimer;
  // 悔棋请求是否挂起中（请求方视角）
  bool _undoPending = false;
  int _blackStoneCount = 0;
  int _whiteStoneCount = 0;

  Player get myPlayerColor => _network.myColor;

  /// 对手执子：优先用服务器告知的颜色，回退为"我的相反色"
  Player get _oppColor => _network.opponentColor ?? myPlayerColor.opponent();

  /// 本局是否已结束（结算已收到或已投降）
  bool get _gameOver => _ended || _engine.gameState != GameState.playing;

  @override
  void initState() {
    super.initState();
    if (widget.network != null) {
      _network = widget.network!;
      _ownsNetwork = false;
    } else {
      // 兜底：没有共享实例时自建（正常流程不会发生）
      _network = NetworkService(hostIp: StorageService().serverIp);
      _ownsNetwork = true;
    }
    _opponentName = _network.opponentName ?? '对手';
    _connectivityStatus = _network.isConnected ? 'connected' : 'offline';
    _engine = GameEngine(boardSize: BoardSize.standard);
    _setupNetworkCallbacks();
    _syncCounts();
    // 导航窗口期缓存的对手消息，首帧渲染后补发（此时 setState 安全）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _network.flushPendingChat();
    });
  }

  void _setupNetworkCallbacks() {
    _network.onConnected = () {
      if (!mounted) return;
      setState(() => _connectivityStatus = 'connected');
    };
    _network.onDisconnected = () {
      if (!mounted) return;
      setState(() => _connectivityStatus = 'offline');
    };
    _network.onOpponentJoined = (_) {
      if (!mounted) return;
      setState(() {
        _oppReady = true;
        _opponentName = _network.opponentName ?? '对手';
      });
    };
    _network.onOpponentMove = (pos, player) {
      if (!mounted) return;
      if (_engine.gameState != GameState.playing) return;
      _engine.makeMove(pos.row, pos.col);
      _lastMove = pos;
      _isMyTurn = _network.yourTurn;
      _syncCounts();
      _checkResult();
    };
    _network.onGameStarted = () {
      if (!mounted) return;
      setState(() {
        // 原地重开时上一局盘面可能还留在本地引擎里，统一在开局时清台
        _engine.reset();
        _lastMove = null;
        _gameStarted = true;
        _oppReady = true;
        _myReady = true;
        _isMyTurn = _network.yourTurn;
        _opponentName = _network.opponentName ?? '对手';
      });
      _syncCounts();
    };
    _network.onGameEnded = (winner) {
      if (!mounted) return;
      setState(() {
        _ended = true;
        _isMyTurn = false;
        if (winner == null) {
          _winnerText = '对局结束（平局或对手离开）。';
        } else if (winner == myPlayerColor) {
          _winnerText = '你赢了！${winner.cn}获胜，恭喜！';
        } else {
          _winnerText = '${winner.cn}胜！对手获胜，再接再厉。';
        }
        _showGameOver = true;
      });
    };
    _network.onChatMessage = (message, sender) {
      if (!mounted) return;
      // 服务器已不回显给发送者，这里收到的必然是对手消息
      setState(() {
        _chatHistory
            .add(_ChatMessage(sender: sender, text: message, isMine: false));
        _opponentName = sender;
      });
      // 面板没打开时浮一条短气泡，避免漏看
      if (!_chatVisible) _showChatBubble('$sender：$message');
    };
    _network.onError = (error, sender) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$sender: $error'),
            backgroundColor: Colors.redAccent),
      );
    };
    // ---------- 悔棋 ----------
    _network.onUndoAsk = (name) {
      if (!mounted) return;
      _showUndoAskDialog(name);
    };
    _network.onUndoAnswer = (accept, reason) {
      if (!mounted) return;
      setState(() => _undoPending = false);
      if (!accept) {
        const texts = {
          'rejected': '对手拒绝了悔棋',
          'stale': '悔棋失败：期间棋盘已变化',
          'no-move': '现在没有可悔的棋（需在你落子后请求）',
          'not-playing': '本局未进行中，无法悔棋',
          'busy': '已有悔棋请求在处理中',
          'left': '对方离开了房间，悔棋取消',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(texts[reason] ?? '悔棋未生效'),
              backgroundColor: Colors.orange),
        );
      }
    };
    _network.onUndone = (removed, nextPlayer) {
      if (!mounted) return;
      setState(() {
        _undoPending = false;
        for (var i = 0; i < removed.length; i++) {
          _engine.undoMove();
        }
        _lastMove = _engine.moveHistory.isNotEmpty
            ? _engine.moveHistory.last.position
            : null;
        _isMyTurn = nextPlayer == myPlayerColor;
      });
      _syncCounts();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '悔棋成功，撤销 ${removed.length} 步 · ${_isMyTurn ? '轮到你落子' : '等待对手落子'}'),
            backgroundColor: Colors.green),
      );
    };
    _network.onUndoCancelled = () {
      if (!mounted) return;
      // 我是被请求方：弹窗直接消失即可；我是请求方由 onUndoAnswer('left') 处理
      Navigator.of(context, rootNavigator: true).maybePop();
    };
    _network.onMessage = (msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
    };
  }

  void _syncCounts() {
    setState(() {
      _blackStoneCount = _countStones(CellState.black);
      _whiteStoneCount = _countStones(CellState.white);
    });
  }

  int _countStones(CellState state) {
    int count = 0;
    for (final row in _engine.board) {
      for (final cell in row) {
        if (cell == state) count++;
      }
    }
    return count;
  }

  void _showChatBubble(String text) {
    _chatBubbleTimer?.cancel();
    setState(() => _chatBubbleText = text);
    _chatBubbleTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _chatBubbleText = null);
    });
  }

  @override
  void dispose() {
    _chatBubbleTimer?.cancel();
    _chatController.dispose();
    if (_gameStarted &&
        _engine.gameState == GameState.playing &&
        !_showGameOver &&
        !_ended) {
      _network.resign();
    }
    _network.leaveRoom();
    if (_ownsNetwork) {
      _network.dispose();
    } else {
      // 连接由大厅持有，这里只解除回调，不能断开 socket
      _network.clearCallbacks();
    }
    super.dispose();
  }

  void _onCellTapped(int row, int col) {
    if (_showGameOver || _gameOver) return;
    if (!_gameStarted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('等待对手准备，开局后方可落子'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (!_network.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('网络已断开，无法落子！'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (!_isMyTurn || _engine.currentPlayer != myPlayerColor) return;

    if (_engine.makeMove(row, col)) {
      _lastMove = Position(row: row, col: col);
      _network.makeMove(row, col);
      setState(() => _isMyTurn = false);
      _syncCounts();
      _checkResult();
    }
  }

  void _checkResult() {
    if (_engine.gameState != GameState.playing) {
      setState(() {
        switch (_engine.gameState) {
          case GameState.blackWon:
            _winnerText = myPlayerColor == Player.black
                ? '你赢了！黑方五连获胜，恭喜！'
                : '黑方五连获胜，对手赢了。';
          case GameState.whiteWon:
            _winnerText = myPlayerColor == Player.white
                ? '你赢了！白方五连获胜，恭喜！'
                : '白方五连获胜，对手赢了。';
          case GameState.draw:
            _winnerText = '棋盘已满，本局平局！';
          default:
            break;
        }
        _showGameOver = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThemePalette.all[StorageService().themeIndex];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_gameStarted &&
            _engine.gameState == GameState.playing &&
            !_showGameOver &&
            !_ended) {
          _network.resign();
        }
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.bgColor, palette.boardBgColor],
            ),
          ),
          // 渐变背景铺满全屏；内容用 SafeArea 避开状态栏/刘海与底部手势条
          child: SafeArea(
            child: Stack(children: [
              // ==================== 主内容列 ====================
              Column(children: [
                _buildTopBar(palette),
                Expanded(
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '黑子: $_blackStoneCount 枚 | 白子: $_whiteStoneCount 枚',
                        style: TextStyle(
                            fontSize: 13,
                            color: palette.secondaryColor,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    Expanded(
                      flex: 6,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: BoardWidget(
                          board: _engine.board,
                          gameState: _engine.gameState,
                          currentPlayer: _engine.currentPlayer,
                          lastMove: _lastMove,
                          themeIndex: StorageService().themeIndex,
                          onTapCell: _onCellTapped,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Chip(
                            label: Text('你执${myPlayerColor.cn}',
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor:
                                palette.primaryColor.withValues(alpha: 0.15),
                            side: BorderSide(
                                color: palette.primaryColor
                                    .withValues(alpha: 0.3)),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: _engine.currentPlayer.toColor(),
                            child: _engine.currentPlayer == Player.black
                                ? null
                                : Icon(Icons.circle,
                                    size: 14, color: Colors.white),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            !_gameStarted
                                ? '等待开局...'
                                : (_isMyTurn ? '轮到你落子！' : '等待对手...'),
                            style: TextStyle(
                              fontSize: 13,
                              color: _isMyTurn
                                  ? palette.primaryColor
                                  : palette.secondaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_gameStarted && !_isMyTurn && !_showGameOver) ...[
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
                          ],
                        ],
                      ),
                    ),
                  ]),
                ),
                _buildBottomBar(palette),
              ]),

              // ==================== 等待开局遮罩 ====================
              if (!_gameStarted && !_showGameOver)
                Positioned.fill(child: _buildWaitingOverlay(palette)),

              // ==================== 聊天面板 ====================
              if (_chatVisible) _buildChatPanel(palette),

              // ==================== 局内消息气泡（面板未打开时的短提示）====================
              if (_chatBubbleText != null && !_chatVisible)
                Positioned(
                  top: 60,
                  left: 24,
                  right: 24,
                  child: IgnorePointer(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded,
                                  size: 14, color: Colors.white70),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _chatBubbleText!,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ==================== 对局结束遮罩 ====================
              if (_showGameOver)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Center(child: _buildGameOverDialog(palette)),
                  ),
                ),

              // ==================== 复盘横幅：结束但已关闭结算提示时 ====================
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
                          const Text('本局已结束 · 复盘模式',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13)),
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
            ]),
          ),
        ),
      ),
    );
  }

  // ---------- Builders ----------

  Widget _buildWaitingOverlay(ThemePalette palette) {
    final text = !_network.isConnected
        ? '与服务器连接已断开，请返回大厅重连'
        : (_oppReady
            ? '双方已进入房间。请点击右上角的“未准备”按钮，'
                '两人都变“已准备”后自动开局。'
            : '等待对手准备…\n房间码：${widget.roomId ?? _network.roomId ?? '-'}\n'
                '（新朋友：把这 6 位数字发给好友，在“加入房间”里输入；'
                '老朋友重开：对方在他手机上进“再来一局”即可）');
    return IgnorePointer(
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.5)),
          ]),
        ),
      ),
    );
  }

  Widget _buildTopBar(ThemePalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(children: [
        IconButton(
          onPressed: () {
            if (_gameStarted &&
                _engine.gameState == GameState.playing &&
                !_showGameOver &&
                !_ended) {
              _network.resign();
            }
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
        ),
        CircleAvatar(
          radius: 14,
          backgroundColor: _oppColor.toColor(),
          child: _oppColor == Player.black
              ? null
              : Icon(Icons.circle, size: 16, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_opponentName,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
            Text(_oppColor == Player.black ? '执黑' : '执白',
                style: TextStyle(fontSize: 11, color: palette.secondaryColor)),
          ]),
        ),
        StatusDot(status: _connectivityStatus),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            if (_myReady) return;
            setState(() => _myReady = true);
            _network.startGame();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _myReady ? Colors.green.shade100 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _myReady ? Colors.green : Colors.grey, width: 1),
            ),
            child: Text(_myReady ? '已准备' : '未准备',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _myReady
                        ? Colors.green.shade800
                        : Colors.grey.shade700)),
          ),
        ),
      ]),
    );
  }

  Widget _buildBottomBar(ThemePalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionBtn(
              icon: Icons.flag_outlined,
              label: '投降',
              danger: true,
              onTap: () => _confirmResign(palette)),
          _actionBtn(
              icon: Icons.undo_rounded,
              label: _undoPending ? '等待答复' : '悔棋',
              onTap: _requestUndo),
          _actionBtn(
              icon: Icons.chat_bubble_outline_rounded,
              label: '聊天',
              onTap: () => setState(() {
                    _chatVisible = !_chatVisible;
                    // 打开面板就地看完整记录，气泡让位
                    if (_chatVisible) _chatBubbleText = null;
                  })),
          _actionBtn(
              icon: Icons.exit_to_app_rounded,
              label: '离开',
              onTap: () {
                _network.leaveRoom();
                Navigator.of(context).pop();
              }),
        ],
      ),
    );
  }

  Widget _actionBtn(
      {required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool danger = false}) {
    return GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: danger
                      ? Colors.red.shade100
                      : Colors.blue.withValues(alpha: 0.12),
                  border: Border.all(
                      color: danger
                          ? Colors.red.shade300
                          : Colors.blue.withValues(alpha: 0.3),
                      width: 1.5),
                ),
                child: Icon(icon,
                    size: 22, color: danger ? Colors.red : Colors.blue)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.blue)),
          ],
        ));
  }

  Widget _buildChatPanel(ThemePalette palette) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: 250,
        decoration: BoxDecoration(
          color: palette.bgColor.withValues(alpha: 0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, -2))
          ],
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: palette.primaryColor.withValues(alpha: 0.3)),
                  bottom: BorderSide(
                      color: palette.primaryColor.withValues(alpha: 0.2))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('局内聊天',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: palette.primaryColor)),
                IconButton(
                    onPressed: () => setState(() => _chatVisible = false),
                    icon: const Icon(Icons.close, size: 20)),
              ],
            ),
          ),
          Expanded(
              child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _chatHistory.length,
            itemBuilder: (ctx, i) =>
                _ChatBubble(message: _chatHistory[i], palette: palette),
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: palette.primaryColor.withValues(alpha: 0.2)))),
            child: Row(children: [
              Expanded(
                  child: TextField(
                controller: _chatController,
                decoration: InputDecoration(
                  hintText: '输入消息...',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendChat(),
              )),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _sendChat,
                icon: const Icon(Icons.send, size: 18),
                label: const Text('发送'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.primaryColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    setState(() =>
        _chatHistory.add(_ChatMessage(sender: '我', text: text, isMine: true)));
    _network.sendChat(text);
    _chatController.clear();
  }

  Widget _buildGameOverDialog(ThemePalette palette) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              _engine.gameState == GameState.draw
                  ? Icons.handshake_outlined
                  : Icons.emoji_events,
              size: 56,
              color: _engine.gameState == GameState.draw
                  ? Colors.orange
                  : palette.primaryColor),
          const SizedBox(height: 16),
          Text('对局结束！',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: palette.primaryColor)),
          const SizedBox(height: 8),
          Text(_winnerText,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: FilledButton.tonal(
                    onPressed: () {
                      _network.leaveRoom();
                      Navigator.of(context).pop();
                    },
                    child: const Text('返回大厅'))),
            const SizedBox(width: 12),
            Expanded(
                child: FilledButton(
                    onPressed: _rematchInRoom,
                    style: FilledButton.styleFrom(
                        backgroundColor: palette.primaryColor),
                    child: const Text('再来一局'))),
          ]),
          const SizedBox(height: 8),
          // 关掉提示，留在页面上查看最终盘面（不会离开房间）
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _showGameOver = false),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('查看棋盘'),
            ),
          ),
        ]),
      ),
    );
  }

  void _confirmResign(ThemePalette palette) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('确认投降'),
              content: const Text('投降后本局棋将结束并判负。确定要放弃吗？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消')),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _network.resign();
                    setState(() {
                      _ended = true;
                      _showGameOver = true;
                      _isMyTurn = false;
                      _winnerText = '你已投降，本局判负。';
                    });
                  },
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('我认输了'),
                ),
              ],
            ));
  }

  // ---------- 悔棋 & 原地重开 ----------

  /// 发出悔棋请求（按钮置灰等答复；服务器校验后可即时驳回）
  void _requestUndo() {
    if (_undoPending) return;
    if (!_gameStarted || _gameOver) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('对局进行中才能悔棋；已结束可点"再来一局"'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _undoPending = true);
    _network.requestUndo();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已向对手发送悔棋请求，等待答复…')),
    );
  }

  /// 被请求方：弹窗征询是否同意悔棋
  void _showUndoAskDialog(String name) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
              title: Text('$name 请求悔棋'),
              content: const Text('同意后将撤销最近的一步（若你已应子则连同应子共撤两步），' '继续由对方落子。'),
              actions: [
                TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _network.replyUndo(false);
                    },
                    child: const Text('拒绝')),
                FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _network.replyUndo(true);
                    },
                    child: const Text('同意')),
              ],
            ));
  }

  /// 结算弹窗"再来一局"：留在房间内，清棋盘并直接按下准备，
  /// 双方都重新准备后服务器自动开新局（房间码不变）
  void _rematchInRoom() {
    _network.startGame();
    setState(() {
      _engine.reset();
      _showGameOver = false;
      _ended = false;
      _gameStarted = false;
      _myReady = true;
      _oppReady = false;
      _isMyTurn = false;
      _lastMove = null;
      _undoPending = false;
      _winnerText = '';
    });
    _syncCounts();
  }
}

// ========== Chat helpers ==========

class _ChatMessage {
  final String sender;
  final String text;
  final bool isMine;
  const _ChatMessage(
      {required this.sender, required this.text, required this.isMine});
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  final ThemePalette palette;
  const _ChatBubble({required this.message, required this.palette});
  @override
  Widget build(BuildContext context) {
    final align = message.isMine ? Alignment.centerRight : Alignment.centerLeft;
    return Align(
        alignment: align,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: message.isMine
                ? palette.primaryColor.withValues(alpha: 0.2)
                : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: message.isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(message.sender,
                  style: TextStyle(
                      fontSize: 11,
                      color: message.isMine
                          ? palette.primaryColor
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(message.text, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ));
  }
}

class StatusDot extends StatelessWidget {
  final String status;
  const StatusDot({super.key, required this.status});
  @override
  Widget build(BuildContext context) {
    Color color;
    String tooltip;
    switch (status) {
      case 'connected':
        color = Colors.green;
        tooltip = '已连接';
        break;
      case 'disconnecting':
        color = Colors.orange;
        tooltip = '断开中...';
        break;
      default:
        color = Colors.red;
        tooltip = '离线';
    }
    return Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: status == 'connected'
                ? [
                    BoxShadow(
                        color: Colors.green.withValues(alpha: 0.4),
                        blurRadius: 6)
                  ]
                : [],
          ),
        ));
  }
}
