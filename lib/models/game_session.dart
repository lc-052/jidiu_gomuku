import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/game_engine.dart';
import '../services/go_engine.dart';
import '../services/go_ai_service.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import 'game_kind.dart';
import 'game_state.dart';

/// Owns local game lifecycle; presentation widgets only observe this session.
class GameSession extends ChangeNotifier {
  final GameKind kind;
  final bool ai;
  final int size;
  final Player human;
  final GoMoveChooser goMoveChooser;
  late final GameEngine gomoku;
  late final GoEngine go;
  Timer? _timer;
  bool _disposed = false;
  bool thinking = false;
  int _revision = 0;
  String? aiError;
  Player? resignedWinner;
  GameSession(
      {required this.kind,
      required this.size,
      this.ai = false,
      this.goMoveChooser = GoAIService.chooseMove})
      : human = StorageService().preferredColor {
    if (kind == GameKind.go) {
      go = GoEngine(size: size);
    } else {
      gomoku = GameEngine(
          boardSize: BoardSize.values.firstWhere((b) => b.size == size));
    }
    _schedule();
  }
  bool get isGo => kind == GameKind.go;
  List<List<CellState>> get board => isGo ? go.board : gomoku.board;
  Player get current => isGo ? go.currentPlayer : gomoku.currentPlayer;
  GameState get state => resignedWinner != null
      ? (resignedWinner == Player.black
          ? GameState.blackWon
          : GameState.whiteWon)
      : (isGo ? go.gameState : gomoku.gameState);
  bool get over => state != GameState.playing;
  bool get scoring => isGo && go.scoring;
  int get moves => isGo ? go.moveCount : gomoku.moveHistory.length;
  Position? get last => isGo
      ? go.lastMove
      : (gomoku.moveHistory.isEmpty ? null : gomoku.moveHistory.last.position);
  bool get canUndo => moves > (ai && human == Player.white ? 1 : 0);
  String get status => over
      ? (state == GameState.draw
          ? '本局和棋'
          : '${state == GameState.blackWon ? "黑方" : "白方"}获胜')
      : scoring
          ? (ai ? '确认死子 · 核对计分' : '确认死子 · 双方共同核对')
          : aiError != null
              ? '电脑暂时无法落子，请重试'
              : thinking
                  ? '电脑正在思考…'
                  : isGo && ai && go.passes == 1 && current == human
                      ? '电脑已停着 · 轮到${human.cn}'
                      : '轮到${current.cn}落子';
  String? play(int r, int c) {
    if (over || thinking) return null;
    if (scoring) {
      go.toggleDead(r, c);
      notifyListeners();
      return null;
    }
    if (ai && current != human) return null;
    final moved = isGo ? go.makeMove(r, c) : gomoku.makeMove(r, c);
    if (!moved) return isGo ? go.error : '请在空交叉点落子';
    _schedule();
    notifyListeners();
    return null;
  }

  void pass() {
    if (!isGo || over || scoring || thinking || (ai && current != human)) {
      return;
    }
    go.pass();
    _schedule();
    notifyListeners();
  }

  void finish() {
    if (!isGo) return;
    go.finish();
    notifyListeners();
  }

  void resume() {
    if (!isGo) return;
    go.resume();
    _schedule();
    notifyListeners();
  }

  void resign() {
    if (over || thinking || (ai && !scoring && current != human)) return;
    _cancelAi();
    resignedWinner = ai ? human.opponent() : current.opponent();
    if (isGo) go.resign(player: ai ? human : current);
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _cancelAi();
    resignedWinner = null;
    if (isGo) {
      go.undoMove();
      if (ai && go.currentPlayer != human && go.canUndo) go.undoMove();
    } else {
      gomoku.undoMove();
      if (ai &&
          gomoku.currentPlayer != human &&
          gomoku.moveHistory.isNotEmpty) {
        gomoku.undoMove();
      }
    }
    _schedule();
    notifyListeners();
  }

  void reset() {
    _cancelAi();
    resignedWinner = null;
    if (isGo) {
      go.reset();
    } else {
      gomoku.reset();
    }
    _schedule();
    notifyListeners();
  }

  void _schedule() {
    if (_disposed || !ai || over || scoring || current == human) return;
    _timer?.cancel();
    final revision = ++_revision;
    aiError = null;
    thinking = true;
    _timer = Timer(const Duration(milliseconds: 350), () async {
      if (_disposed || revision != _revision || over || scoring) return;
      if (isGo) {
        try {
          final move = await goMoveChooser(go.fork(),
              Difficulty.values[StorageService().difficultyIndex.clamp(0, 2)]);
          if (_disposed || revision != _revision || over || scoring) return;
          if (move == null) {
            go.pass();
          } else if (!go.makeMove(move.row, move.col)) {
            throw StateError('AI returned an invalid move');
          }
        } catch (_) {
          if (_disposed || revision != _revision) return;
          aiError = '暂时无法落子，请重试';
        }
        thinking = false;
        notifyListeners();
        return;
      }
      final service = AIService(
          boardSize: gomoku.boardSize,
          difficulty:
              Difficulty.values[StorageService().difficultyIndex.clamp(0, 2)],
          aiPlayer: human.opponent());
      final move = service.getBestMove(gomoku, human.opponent());
      if (move != null) gomoku.makeMove(move.row, move.col);
      thinking = false;
      notifyListeners();
    });
  }

  void retryAi() {
    if (thinking || aiError == null) return;
    _schedule();
    notifyListeners();
  }

  void _cancelAi() {
    ++_revision;
    _timer?.cancel();
    thinking = false;
    aiError = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAi();
    super.dispose();
  }
}
