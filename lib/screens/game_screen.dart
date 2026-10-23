import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/game_kind.dart';
import '../models/game_state.dart';
import '../models/game_session.dart';
import '../models/theme_notifier.dart';
import '../services/storage_service.dart';
import '../widgets/board_widget.dart';
import '../widgets/game_cards.dart';
import '../widgets/section_card.dart';
import '../widgets/adaptive_card_pair.dart';
import '../widgets/game_result.dart';

class GameScreen extends StatefulWidget {
  final int gameMode;
  final int chosenThemeIndex;
  final GameKind kind;
  const GameScreen(
      {super.key,
      required this.gameMode,
      this.chosenThemeIndex = 0,
      this.kind = GameKind.gomoku});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameSession? _session;
  bool _resultNotified = false;
  late int _size = widget.kind == GameKind.go ? 9 : 15;
  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('确定')),
              ])) ??
      false;
  Future<void> _leave() async {
    if (_session == null ||
        _session!.over ||
        await _confirm('离开对局', '当前棋局不会保存，确定离开吗？')) {
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      }
    }
  }

  void _start() {
    _session?.dispose();
    _resultNotified = false;
    final session =
        GameSession(kind: widget.kind, size: _size, ai: widget.gameMode == 1);
    session.addListener(_onSessionChanged);
    setState(() => _session = session);
  }

  void _onSessionChanged() {
    final session = _session;
    if (session == null || !session.over) {
      _resultNotified = false;
      return;
    }
    if (_resultNotified) return;
    _resultNotified = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && session == _session && session.over) _showResult(session);
    });
  }

  GameResultDetails _resultDetails(GameSession s) => GameResultDetails(
        title: s.status,
        reason: endReason(s.resignedWinner != null
            ? 'resign'
            : s.isGo
                ? 'score'
                : s.state == GameState.draw
                    ? 'draw'
                    : 'five-in-a-row'),
        size: s.size,
        moves: s.moves,
        last: s.last,
        players:
            s.ai ? '你执${s.human.cn} · 电脑执${s.human.opponent().cn}' : '同屏双人对局',
        score: s.isGo && s.resignedWinner == null
            ? '黑 ${s.go.score().black.toStringAsFixed(1)} · 白 ${s.go.score().white.toStringAsFixed(1)}'
            : null,
      );

  Future<void> _showResult(GameSession s) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: const Text('对局结束'),
              content: SingleChildScrollView(child: _resultDetails(s)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('查看棋盘')),
                FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      s.reset();
                    },
                    child: const Text('再来一局'))
              ]));

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return PopScope(
      canPop: session == null || session.over,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
            leading: IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _leave),
            title: Text(
                '${widget.kind.label} · ${widget.gameMode == 1 ? "人机练习" : "同屏对弈"}')),
        body: session == null
            ? _setup()
            : ListenableBuilder(
                listenable: session, builder: (context, _) => _game(session)),
      ),
    );
  }

  Widget _setup() => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              children: [
                SectionCard(
                    title: '准备开始',
                    subtitle: widget.kind.description,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('选择棋盘'),
                          const SizedBox(height: 16),
                          Wrap(spacing: 12, runSpacing: 8, children: [
                            for (final size in widget.kind == GameKind.go
                                ? [9, 13, 19]
                                : [9, 15, 19])
                              ChoiceChip(
                                  label: Text('$size × $size'),
                                  selected: _size == size,
                                  onSelected: (_) =>
                                      setState(() => _size = size)),
                          ]),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                              onPressed: _start,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('开始对弈')),
                        ])),
                const SizedBox(height: 16),
                _rules(),
              ])));
  Widget _rules() => SectionCard(
      title: '棋局约定',
      child: Text(widget.kind == GameKind.go
          ? '黑方先行，白贴 7.5 目。采用面积计分（活子 + 围空），禁止自杀与全局同形。连续两次停着后核对死子并计分。人机难度与执子可在设置中选择。'
          : '自由五子棋，不设禁手。横、竖、斜向率先连成五子即获胜。人机模式使用设置中的难度与执子偏好。'));

  Widget _game(GameSession session) =>
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final board = SectionCard(
            child: AspectRatio(
                aspectRatio: 1,
                child: BoardWidget(
                  board: session.board,
                  gameState: session.state,
                  currentPlayer: session.current,
                  lastMove: session.last,
                  winningPositions: !session.isGo &&
                          session.over &&
                          session.resignedWinner == null
                      ? gomokuWinningLine(
                          session.board,
                          session.last,
                          session.state == GameState.blackWon
                              ? Player.black
                              : session.state == GameState.whiteWon
                                  ? Player.white
                                  : null)
                      : const {},
                  themeIndex: context.watch<ThemeNotifier>().chosenThemeIndex,
                  markedPositions: session.isGo ? session.go.dead : const {},
                  onTapCell: (r, c) {
                    final before = session.moves;
                    final error = session.play(r, c);
                    if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(error),
                          duration: const Duration(seconds: 2)));
                    }
                    if (session.moves != before &&
                        StorageService().vibrationEnabled) {
                      HapticFeedback.selectionClick();
                    }
                    if (session.moves != before &&
                        StorageService().soundEnabled) {
                      SystemSound.play(SystemSoundType.click);
                    }
                  },
                )));
        final details =
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PlayerStatusCard(session: session),
          const SizedBox(height: 16),
          if (session.over) ...[
            SectionCard(
                title: '本局结算',
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _resultDetails(session),
                      TextButton(
                          onPressed: () => _showResult(session),
                          child: const Text('查看对局信息')),
                    ])),
            const SizedBox(height: 16),
          ],
          if (session.isGo &&
              (session.scoring ||
                  (session.over && session.resignedWinner == null))) ...[
            GoScoringCard(session: session),
            const SizedBox(height: 16),
          ],
          GameActionsCard(
              session: session,
              onRestart: () async {
                if (await _confirm('重新开始', '确定清空当前棋盘并开始新一局吗？')) {
                  session.reset();
                }
              },
              onResign: () async {
                if (await _confirm('确认认输', '${session.current.cn}确认认输吗？')) {
                  session.resign();
                }
              }),
          const SizedBox(height: 16),
          AdaptiveCardPair(
              breakpoint: 0,
              first: MoveSummaryCard(session: session),
              second: _rules()),
        ]);
        return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Expanded(flex: 7, child: board),
                          const SizedBox(width: 20),
                          Expanded(flex: 4, child: details)
                        ])
                  : Column(
                      children: [board, const SizedBox(height: 16), details]),
            )));
      });
}
