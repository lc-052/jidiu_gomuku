import '../models/game_state.dart';

class GoScore {
  final double black;
  final double white;
  const GoScore(this.black, this.white);
  String get result => black > white
      ? '黑方胜 ${(black - white).toStringAsFixed(1)} 目'
      : '白方胜 ${(white - black).toStringAsFixed(1)} 目';
}

/// Area scoring, no suicide, positional superko. Passes are exempt from superko.
class GoEngine {
  final int size;
  final double komi;
  late List<List<CellState>> _board;
  Player currentPlayer = Player.black;
  GameState gameState = GameState.playing;
  int passes = 0;
  bool scoring = false;
  int blackCaptures = 0;
  int whiteCaptures = 0;
  Position? lastMove;
  String? error;
  final Set<Position> dead = {};
  final List<_GoSnapshot> _history = [];
  final List<String> _positions = [];

  GoEngine({this.size = 9, this.komi = 7.5}) {
    if (![9, 13, 19].contains(size)) throw ArgumentError('围棋支持 9、13、19 路');
    reset();
  }

  List<List<CellState>> get board => _copy(_board);
  int get moveCount => _history.length;
  bool get canUndo => _history.isNotEmpty;

  /// Independent analysis position, retaining superko history but no undo stack.
  /// Search and background isolates never mutate the live match.
  GoEngine fork() {
    final copy = GoEngine(size: size, komi: komi);
    copy._board = _copy(_board);
    copy.currentPlayer = currentPlayer;
    copy.gameState = gameState;
    copy.passes = passes;
    copy.scoring = scoring;
    copy.blackCaptures = blackCaptures;
    copy.whiteCaptures = whiteCaptures;
    copy.lastMove = lastMove;
    copy.dead.addAll(dead);
    copy._positions
      ..clear()
      ..addAll(_positions);
    return copy;
  }

  List<List<CellState>> _copy(List<List<CellState>> b) =>
      b.map((r) => List<CellState>.from(r)).toList();
  String _key(List<List<CellState>> b) =>
      b.expand((r) => r).map((c) => c.index).join();

  Iterable<Position> _neighbors(Position p) sync* {
    for (final d in const [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1]
    ]) {
      final r = p.row + d[0], c = p.col + d[1];
      if (r >= 0 && r < size && c >= 0 && c < size) {
        yield Position(row: r, col: c);
      }
    }
  }

  Set<Position> _group(List<List<CellState>> b, Position start) {
    final group = <Position>{start};
    final pending = [start];
    while (pending.isNotEmpty) {
      for (final p in _neighbors(pending.removeLast())) {
        if (b[p.row][p.col] == b[start.row][start.col] && group.add(p)) {
          pending.add(p);
        }
      }
    }
    return group;
  }

  bool _hasLiberty(List<List<CellState>> b, Set<Position> group) => group
      .any((p) => _neighbors(p).any((q) => b[q.row][q.col] == CellState.empty));

  bool makeMove(int row, int col) {
    error = null;
    if (gameState != GameState.playing || scoring) return false;
    if (row < 0 ||
        col < 0 ||
        row >= size ||
        col >= size ||
        _board[row][col] != CellState.empty) {
      error = '请在空交叉点落子';
      return false;
    }
    final next = _copy(_board);
    final pos = Position(row: row, col: col);
    final own = CellState.fromPlayer(currentPlayer);
    next[row][col] = own;
    int captured = 0;
    for (final p in _neighbors(pos)) {
      if (next[p.row][p.col] != CellState.empty && next[p.row][p.col] != own) {
        final group = _group(next, p);
        if (!_hasLiberty(next, group)) {
          captured += group.length;
          for (final q in group) {
            next[q.row][q.col] = CellState.empty;
          }
        }
      }
    }
    if (!_hasLiberty(next, _group(next, pos))) {
      error = '禁入点：落子后己方无气';
      return false;
    }
    final key = _key(next);
    if (_positions.contains(key)) {
      error = '劫争：不能重复之前的局面，请先在别处落子';
      return false;
    }
    _save();
    _board = next;
    _positions.add(key);
    if (currentPlayer == Player.black) {
      blackCaptures += captured;
    } else {
      whiteCaptures += captured;
    }
    lastMove = pos;
    currentPlayer = currentPlayer.opponent();
    passes = 0;
    return true;
  }

  void _save() => _history.add(_GoSnapshot(
      _copy(_board),
      currentPlayer,
      passes,
      scoring,
      blackCaptures,
      whiteCaptures,
      lastMove,
      List.of(_positions),
      Set.of(dead),
      gameState));

  bool pass() {
    if (scoring || gameState != GameState.playing) return false;
    _save();
    passes++;
    lastMove = null;
    currentPlayer = currentPlayer.opponent();
    scoring = passes >= 2;
    return true;
  }

  void toggleDead(int row, int col) {
    if (row < 0 || col < 0 || row >= size || col >= size) return;
    if (!scoring || _board[row][col] == CellState.empty) return;
    final group = _group(_board, Position(row: row, col: col));
    if (dead.contains(group.first)) {
      dead.removeAll(group);
    } else {
      dead.addAll(group);
    }
  }

  GoScore score() {
    final b = _copy(_board);
    for (final p in dead) {
      b[p.row][p.col] = CellState.empty;
    }
    double black = 0, white = komi;
    final visited = <Position>{};
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (b[r][c] == CellState.black) {
          black++;
          continue;
        }
        if (b[r][c] == CellState.white) {
          white++;
          continue;
        }
        final p = Position(row: r, col: c);
        if (visited.contains(p)) continue;
        final region = _group(b, p);
        visited.addAll(region);
        final borders = <CellState>{};
        for (final q in region) {
          for (final n in _neighbors(q)) {
            if (b[n.row][n.col] != CellState.empty) {
              borders.add(b[n.row][n.col]);
            }
          }
        }
        if (borders.length == 1) {
          if (borders.first == CellState.black) {
            black += region.length;
          } else {
            white += region.length;
          }
        }
      }
    }
    return GoScore(black, white);
  }

  void resume() {
    if (gameState != GameState.playing) return;
    scoring = false;
    passes = 0;
    dead.clear();
  }

  void finish() {
    if (!scoring || gameState != GameState.playing) return;
    final result = score();
    gameState =
        result.black > result.white ? GameState.blackWon : GameState.whiteWon;
    scoring = false;
  }

  void resign({Player? player}) {
    if (gameState != GameState.playing) return;
    _save();
    gameState = (player ?? currentPlayer) == Player.black
        ? GameState.whiteWon
        : GameState.blackWon;
    scoring = false;
  }

  bool undoMove() {
    if (_history.isEmpty) return false;
    final s = _history.removeLast();
    _board = s.board;
    currentPlayer = s.player;
    passes = s.passes;
    scoring = s.scoring;
    blackCaptures = s.black;
    whiteCaptures = s.white;
    lastMove = s.last;
    _positions
      ..clear()
      ..addAll(s.positions);
    dead
      ..clear()
      ..addAll(s.dead);
    gameState = s.state;
    error = null;
    return true;
  }

  void reset() {
    _board = List.generate(size, (_) => List.filled(size, CellState.empty));
    currentPlayer = Player.black;
    gameState = GameState.playing;
    passes = 0;
    scoring = false;
    blackCaptures = 0;
    whiteCaptures = 0;
    lastMove = null;
    dead.clear();
    _history.clear();
    _positions
      ..clear()
      ..add(_key(_board));
    error = null;
  }
}

class _GoSnapshot {
  final List<List<CellState>> board;
  final Player player;
  final int passes, black, white;
  final bool scoring;
  final Position? last;
  final List<String> positions;
  final Set<Position> dead;
  final GameState state;
  _GoSnapshot(this.board, this.player, this.passes, this.scoring, this.black,
      this.white, this.last, this.positions, this.dead, this.state);
}
