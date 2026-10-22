import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../models/game_kind.dart';
import '../models/game_state.dart';
import '../models/online_room_state.dart';
import '../services/network_service.dart';
import '../services/storage_service.dart';
import '../widgets/adaptive_card_pair.dart';
import '../widgets/board_widget.dart';
import '../widgets/section_card.dart';

class OnlineGameScreen extends StatefulWidget {
  final NetworkService? network;
  final String? roomId;
  final String playerColor;
  const OnlineGameScreen(
      {super.key, this.network, this.roomId, this.playerColor = 'black'});
  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  late final NetworkService _network;
  OnlineRoomState? _state;
  bool _connected = false,
      _closed = false,
      _pending = false,
      _chatVisible = false;
  String? _roomMessage;
  Timer? _requestTimer;
  DialogRoute<bool>? _undoDialog;
  final _chat = TextEditingController();
  final List<String> _messages = [];
  bool get _active => _state?.phase == 'playing' || _state?.phase == 'scoring';
  bool get _canAct =>
      _connected && !_closed && !_pending && _network.roomId != null;
  String get _myKey => _network.myColor == Player.black ? 'black' : 'white';

  @override
  void initState() {
    super.initState();
    _network =
        widget.network ?? NetworkService(hostIp: StorageService().serverIp);
    _state = _network.latestState;
    _connected = _network.isConnected;
    _network.onState = (value) {
      if (!mounted) return;
      final oldMoves = _state?.moves;
      _requestTimer?.cancel();
      setState(() {
        _state = value;
        _pending = false;
      });
      if (oldMoves != null &&
          value.moves > oldMoves &&
          StorageService().vibrationEnabled) {
        HapticFeedback.selectionClick();
      }
    };
    _network.onConnected = () {
      if (!mounted) return;
      setState(() {
        _connected = true;
        _closed = true;
        _roomMessage = '连接已恢复，请返回大厅重新进房';
      });
    };
    _network.onDisconnected = () {
      if (!mounted) return;
      _requestTimer?.cancel();
      _cancelUndo();
      setState(() {
        _connected = false;
        _closed = true;
        _pending = false;
        _roomMessage = '连接已断开，本局不能继续，请返回大厅重新连接';
      });
    };
    _network.onRoomClosed = (message) {
      if (!mounted) return;
      _cancelUndo();
      _requestTimer?.cancel();
      setState(() {
        _closed = true;
        _pending = false;
        _roomMessage = message;
      });
    };
    _network.onError = (message, _) {
      if (!mounted) return;
      _requestTimer?.cancel();
      setState(() => _pending = false);
      _notice(message);
    };
    _network.onChatMessage = (message, sender) {
      if (!mounted) return;
      setState(() => _messages.add('$sender：$message'));
      if (_messages.length > 100) _messages.removeAt(0);
      if (!_chatVisible) _notice('$sender：$message');
    };
    _network.onUndoAsk = _askUndo;
    _network.onUndoCancelled = _cancelUndo;
    _network.onUndoAnswer = (accept, reason) {
      if (!mounted) return;
      _requestTimer?.cancel();
      setState(() => _pending = false);
      if (!accept) {
        _notice(reason == 'rejected'
            ? '对手拒绝了悔棋'
            : reason == 'timeout'
                ? '悔棋请求已超时'
                : '悔棋请求已失效');
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _network.flushPendingChat();
      if (_connected && _network.roomId != null) _network.requestState();
    });
  }

  void _notice(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(value), duration: const Duration(seconds: 2)));
    }
  }

  void _send(VoidCallback action) {
    if (!_canAct) return;
    setState(() => _pending = true);
    _requestTimer?.cancel();
    _requestTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() => _pending = false);
      _notice('服务器暂未确认，请检查连接');
      if (_network.isConnected && _network.roomId != null) {
        _network.requestState();
      }
    });
    action();
  }

  void _cancelUndo() {
    final route = _undoDialog;
    _undoDialog = null;
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _askUndo(String name) async {
    if (!mounted || _undoDialog != null) return;
    final route = DialogRoute<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('悔棋请求'),
                content: Text('$name 希望撤回上一轮走棋，是否同意？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('拒绝')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('同意')),
                ]));
    _undoDialog = route;
    final accept = await Navigator.of(context).push(route);
    if (!mounted || _undoDialog != route) return;
    _undoDialog = null;
    if (!_closed) _network.replyUndo(accept == true);
  }

  Future<void> _confirmResign() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('确认认输'),
                content: const Text('认输后本局立即结束。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('继续下棋')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('认输')),
                ]));
    if (mounted && ok == true) _send(_network.resign);
  }

  Future<void> _leave() async {
    if (_active && !_closed) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('离开对局'),
                  content: const Text('对局中离开将判负，确定离开吗？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('继续下棋')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('离开')),
                  ]));
      if (ok != true) return;
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _requestTimer?.cancel();
    _chat.dispose();
    _network.clearCallbacks();
    _network.leaveRoom();
    if (widget.network == null) _network.dispose();
    super.dispose();
  }

  void _tap(int r, int c) {
    final state = _state;
    if (state == null || !_canAct) return;
    if (state.phase == 'scoring') {
      _send(() => _network.sendRoomAction(
          'markDead', {'row': r, 'col': c, 'revision': state.revision}));
    } else if (state.phase == 'playing' && state.current == _network.myColor) {
      _send(() => _network.makeMove(r, c));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return PopScope(
        canPop: !_active || _closed,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(
              leading: IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _leave),
              title:
                  Text('在线棋室 · ${s?.kind.label ?? _network.roomKind.label}')),
          body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_roomMessage != null || !_connected) ...[
                        SectionCard(
                            title: _connected ? '房间提示' : '网络未连接',
                            child: Wrap(spacing: 12, runSpacing: 8, children: [
                              Text(_roomMessage ?? '请返回大厅连接服务器'),
                              TextButton(
                                  onPressed: _leave, child: const Text('返回大厅')),
                            ])),
                        const SizedBox(height: 16),
                      ],
                      if (s == null)
                        const SectionCard(
                            title: '等待棋局', child: Text('进入房间后将在这里显示棋盘与准备状态。'))
                      else
                        AdaptiveCardPair(
                            firstFlex: 7,
                            secondFlex: 4,
                            breakpoint: 900,
                            first: SectionCard(
                                title: '${s.size} × ${s.size} · ${s.status}',
                                subtitle: '房间码：${s.roomId}',
                                trailing: IconButton(
                                    tooltip: '复制房间码',
                                    icon: const Icon(Icons.copy_rounded),
                                    onPressed: () => Clipboard.setData(
                                        ClipboardData(text: s.roomId))),
                                child: AspectRatio(
                                    aspectRatio: 1,
                                    child: BoardWidget(
                                        board: s.board,
                                        gameState: s.finished
                                            ? (s.winner == null
                                                ? GameState.draw
                                                : s.winner == Player.black
                                                    ? GameState.blackWon
                                                    : GameState.whiteWon)
                                            : GameState.playing,
                                        currentPlayer: s.current,
                                        lastMove: s.last,
                                        markedPositions: s.dead,
                                        themeIndex: StorageService().themeIndex,
                                        onTapCell: _tap))),
                            second: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _players(s),
                                  const SizedBox(height: 16),
                                  if (s.phase == 'waiting') ...[
                                    _ready(s),
                                    const SizedBox(height: 16)
                                  ],
                                  if (s.phase == 'scoring' ||
                                      (s.finished && s.reason == 'score')) ...[
                                    _scoring(s),
                                    const SizedBox(height: 16)
                                  ],
                                  if (s.finished) ...[
                                    _result(s),
                                    const SizedBox(height: 16)
                                  ],
                                  _actions(s),
                                  const SizedBox(height: 16),
                                  SectionCard(
                                      title: '棋局记录',
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('已行 ${s.moves} 手'),
                                            if (s.last != null)
                                              Text(
                                                  '最近落子：${s.last!.row + 1} 行 ${s.last!.col + 1} 列'),
                                            if (s.kind == GameKind.go)
                                              Text('连续停着：${s.passes} / 2'),
                                            if (_pending)
                                              const Padding(
                                                  padding:
                                                      EdgeInsets.only(top: 12),
                                                  child:
                                                      LinearProgressIndicator()),
                                          ])),
                                ])),
                      if (_chatVisible) ...[
                        const SizedBox(height: 16),
                        _chatCard()
                      ],
                    ]),
              ))),
        ));
  }

  Widget _players(OnlineRoomState s) => SectionCard(
      title: '对弈双方',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final p in s.players)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(Icons.circle,
                    size: 16,
                    color: p['color'] == 'black'
                        ? const Color(0xFF383838)
                        : const Color(0xFFD6D4CE)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        '${p['name']}${p['color'] == _myKey ? " · 你" : ""} · ${p['color'] == 'black' ? "执黑" : "执白"}')),
                if (s.phase == 'waiting')
                  Text(p['ready'] == true ? '已准备' : '未准备'),
              ])),
        if (s.kind == GameKind.go)
          Text('提子：黑 ${s.captures['black']} · 白 ${s.captures['white']}'),
      ]));
  Widget _ready(OnlineRoomState s) => SectionCard(
      title: '准备开局',
      subtitle: s.players.length < 2 ? '把房间码发给好友，等待对方加入' : '双方准备后自动开局',
      child: FilledButton.tonal(
          onPressed:
              _canAct && s.players.length == 2 && !s.isReady(_network.myColor)
                  ? () => _send(_network.startGame)
                  : null,
          child: Text(s.isReady(_network.myColor) ? '已准备' : '准备')));
  Widget _scoring(OnlineRoomState s) => SectionCard(
      title: s.finished ? '面积计分' : '终局核对',
      subtitle: '白贴 7.5 目。点击棋子标记或取消整块死子；修改后双方需重新确认。有争议可继续下棋。',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('黑 ${s.score?['black']} · 白 ${s.score?['white']}',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (!s.finished)
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
                onPressed: _canAct && !s.confirmations.contains(_myKey)
                    ? () => _send(() => _network.sendRoomAction(
                        'confirmScore', {'revision': s.revision}))
                    : null,
                child: Text(
                    s.confirmations.contains(_myKey) ? '已确认，等待对手' : '确认计分')),
            OutlinedButton(
                onPressed: _canAct
                    ? () => _send(() => _network.sendRoomAction('resumePlay'))
                    : null,
                child: const Text('继续下棋')),
          ]),
      ]));
  Widget _result(OnlineRoomState s) => SectionCard(
      title: s.status,
      subtitle: s.reason == 'resign'
          ? '本局以认输结束'
          : s.reason == 'disconnected' || s.reason == 'left'
              ? '对手离开，对局结束'
              : s.reason == 'score'
                  ? '双方已确认终局计分'
                  : '本局已结束，可保留棋盘查看',
      child: FilledButton.tonal(
          onPressed: _canAct ? () => _send(_network.startGame) : null,
          child: const Text('再来一局')));
  Widget _actions(OnlineRoomState s) => SectionCard(
      title: '对局操作',
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        if (_active) ...[
          if (s.kind == GameKind.go && s.phase == 'playing')
            FilledButton.tonalIcon(
                onPressed: _canAct && s.current == _network.myColor
                    ? () => _send(() => _network.sendRoomAction('pass'))
                    : null,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('停一手')),
          OutlinedButton.icon(
              onPressed: _canAct && s.moves > 0 && !s.undoPending
                  ? () => _send(_network.requestUndo)
                  : null,
              icon: const Icon(Icons.undo_rounded),
              label: Text(s.undoPending ? '等待悔棋答复' : '悔棋')),
          TextButton.icon(
              onPressed: _canAct ? _confirmResign : null,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('认输')),
        ],
        TextButton.icon(
            onPressed: () => setState(() => _chatVisible = !_chatVisible),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('聊天')),
        TextButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.exit_to_app_rounded),
            label: const Text('离开')),
      ]));
  Widget _chatCard() => SectionCard(
      title: '局内聊天',
      child: Column(children: [
        SizedBox(
            height: 160,
            child: ListView(
                reverse: true,
                children: _messages.reversed
                    .map((m) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(m)))
                    .toList())),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: TextField(
                  controller: _chat,
                  maxLength: 100,
                  decoration: const InputDecoration(hintText: '输入消息'))),
          const SizedBox(width: 8),
          IconButton.filled(
              tooltip: '发送',
              onPressed: _connected && !_closed
                  ? () {
                      final value = _chat.text.trim();
                      if (value.isEmpty) return;
                      _network.sendChat(value);
                      setState(() => _messages.add('你：$value'));
                      _chat.clear();
                    }
                  : null,
              icon: const Icon(Icons.send_rounded)),
        ]),
      ]));
}
