import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/game_state.dart';
import 'go_engine.dart';

typedef GoMoveChooser = Future<Position?> Function(
    GoEngine position, Difficulty difficulty);

/// Offline heuristic Go opponent. Null means pass, never an illegal move.
class GoAIService {
  final Difficulty difficulty;
  final math.Random _random;
  GoAIService({this.difficulty = Difficulty.medium, math.Random? random})
      : _random = random ?? math.Random();

  /// A detached position keeps captures, superko, and the undo stack isolated.
  static Future<Position?> chooseMove(
          GoEngine position, Difficulty difficulty) =>
      compute(
          _computeGoMove, (position: position.fork(), difficulty: difficulty));

  Position? getBestMove(GoEngine position) {
    if (position.gameState != GameState.playing || position.scoring) {
      return null;
    }
    final search = position.fork();
    final ranked = _rank(search);
    if (ranked.isEmpty || ranked.first.score <= 0) return null;

    if (difficulty == Difficulty.easy) {
      // Urgent captures and escapes stay reliable even at beginner difficulty.
      final best = ranked.first;
      final choices = ranked
          .where((m) =>
              m.score > 0 &&
              m.score >= best.score - (best.tactical >= 100 ? 5 : 12))
          .take(5)
          .toList();
      return choices[_random.nextInt(choices.length)].position;
    }
    if (difficulty == Difficulty.medium) return ranked.first.position;

    // Examine the strongest tactical reply to each short-listed move.
    _Candidate? best;
    double bestValue = -double.infinity;
    for (final move in ranked.take(6)) {
      if (!search.makeMove(move.position.row, move.position.col)) continue;
      final replies = _rank(search, tacticalOnly: true);
      final risk =
          replies.isEmpty ? 0.0 : math.max(0.0, replies.first.tactical);
      search.undoMove();
      final value = move.score - risk * .75;
      if (value > bestValue) {
        bestValue = value;
        best = move;
      }
    }
    return best?.position ?? ranked.first.position;
  }

  List<_Candidate> _rank(GoEngine engine, {bool tacticalOnly = false}) {
    final before = _Analysis(engine.board);
    final own = CellState.fromPlayer(engine.currentPlayer);
    final enemy = own == CellState.black ? CellState.white : CellState.black;
    final ranked = <_Candidate>[];
    final capturesBefore = engine.currentPlayer == Player.black
        ? engine.blackCaptures
        : engine.whiteCaptures;
    for (int i = 0; i < before.cells.length; i++) {
      if (before.cells[i] != CellState.empty || before.isEye(i, own)) continue;
      final adjacent = before
          .neighbors(i)
          .map((p) => before.groups[p])
          .whereType<_Group>()
          .toSet();
      // For reply search, all direct captures and atari escapes are sufficient.
      if (tacticalOnly && !adjacent.any((g) => g.liberties.length <= 2)) {
        continue;
      }
      final row = i ~/ before.size, col = i % before.size;
      if (!engine.makeMove(row, col)) continue;
      final capturesAfter =
          own == CellState.black ? engine.blackCaptures : engine.whiteCaptures;
      final captured = capturesAfter - capturesBefore;
      final after = _Analysis(engine.board, regions: false);
      final placed = after.groups[i]!;
      double tactical = captured * 180;
      for (final group in adjacent) {
        if (group.color == own) {
          if (group.liberties.length == 1 && placed.liberties.length > 1) {
            tactical += 140 + group.stones.length * 50;
          } else if (group.liberties.length == 2 &&
              placed.liberties.length > 2) {
            tactical += 10 + math.min(group.stones.length, 5) * 2;
          }
        } else if (group.color == enemy && group.liberties.length == 2) {
          final remaining = after.groups[group.stones.first];
          if (remaining != null &&
              remaining.color == enemy &&
              remaining.liberties.length == 1) {
            tactical += 45 + group.stones.length * 12;
          }
        }
      }
      if (placed.liberties.length == 1) {
        final liberty = placed.liberties.first;
        // The actual engine distinguishes a valid ko capture from self-atari.
        if (engine.makeMove(liberty ~/ before.size, liberty % before.size)) {
          tactical -= 260 + placed.stones.length * 100;
          engine.undoMove();
        }
      }
      double strategic = 0;
      if (!tacticalOnly) {
        final edge = math.min(math.min(row, col),
            math.min(before.size - 1 - row, before.size - 1 - col));
        strategic += edge == 0
            ? -12
            : edge == 1
                ? -3
                : edge == 2
                    ? 7
                    : edge == 3
                        ? 6
                        : 3;
        final friendly = adjacent.where((g) => g.color == own).length;
        if (friendly > 1) strategic += (friendly - 1) * 12;
        int distance = before.size * 2;
        for (int j = 0; j < before.cells.length; j++) {
          if (before.cells[j] == own) {
            distance = math.min(distance,
                (row - j ~/ before.size).abs() + (col - j % before.size).abs());
          }
        }
        strategic += distance >= 2 && distance <= 5
            ? 9
            : distance > 5
                ? 3
                : 0;
        final star = before.size == 9 ? 2 : 3;
        final far = before.size - 1 - star;
        final cornerDistance = [star, far]
            .expand((r) =>
                [star, far].map((c) => (row - r).abs() + (col - c).abs()))
            .reduce(math.min);
        if (before.stoneCount < 8) {
          strategic += math.max(0, 12 - cornerDistance * 3);
        }
        final region = before.regions[i];
        // Avoid filling settled territory or throwing stones into small enemy regions.
        if (region != null &&
            region.owner != null &&
            region.length <= before.cells.length * .18) {
          strategic -= region.owner == own ? 60 : 90;
        }
      }
      engine.undoMove();
      ranked.add(_Candidate(
          Position(row: row, col: col), tactical + strategic, tactical));
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }
}

Position? _computeGoMove(
        ({GoEngine position, Difficulty difficulty}) request) =>
    GoAIService(difficulty: request.difficulty).getBestMove(request.position);

class _Candidate {
  final Position position;
  final double score, tactical;
  const _Candidate(this.position, this.score, this.tactical);
}

class _Group {
  final CellState color;
  final Set<int> stones, liberties;
  _Group(this.color, this.stones, this.liberties);
}

class _Region {
  final CellState? owner;
  final int length;
  _Region(this.owner, this.length);
}

/// One flood fill per connected group, using integer intersections.
class _Analysis {
  final int size;
  final List<CellState> cells;
  late final List<_Group?> groups;
  late final List<_Region?> regions;
  int stoneCount = 0;
  _Analysis(List<List<CellState>> board, {bool regions = true})
      : size = board.length,
        cells = board.expand((r) => r).toList() {
    groups = List.filled(cells.length, null);
    this.regions = List.filled(cells.length, null);
    final visited = <int>{};
    for (int start = 0; start < cells.length; start++) {
      if (cells[start] != CellState.empty) stoneCount++;
      if (!visited.add(start)) continue;
      if (!regions && cells[start] == CellState.empty) continue;
      final color = cells[start];
      final stones = <int>{start}, liberties = <int>{};
      final boundary = <CellState>{};
      final pending = [start];
      while (pending.isNotEmpty) {
        for (final q in neighbors(pending.removeLast())) {
          if (cells[q] == color && visited.add(q)) {
            stones.add(q);
            pending.add(q);
          }
          if (cells[q] == CellState.empty) {
            liberties.add(q);
          } else if (cells[q] != color) {
            boundary.add(cells[q]);
          }
        }
      }
      if (color == CellState.empty) {
        final region = _Region(
            boundary.length == 1 ? boundary.first : null, stones.length);
        for (final p in stones) {
          this.regions[p] = region;
        }
      } else {
        final group = _Group(color, stones, liberties);
        for (final p in stones) {
          groups[p] = group;
        }
      }
    }
  }
  Iterable<int> neighbors(int p) sync* {
    if (p >= size) yield p - size;
    if (p < cells.length - size) yield p + size;
    if (p % size > 0) yield p - 1;
    if (p % size < size - 1) yield p + 1;
  }

  bool isEye(int p, CellState color) {
    if (neighbors(p).any((q) => cells[q] != color)) return false;
    final r = p ~/ size, c = p % size;
    int hostile = 0;
    for (final dr in [-1, 1]) {
      for (final dc in [-1, 1]) {
        final rr = r + dr, cc = c + dc;
        if (rr >= 0 && rr < size && cc >= 0 && cc < size) {
          final value = cells[rr * size + cc];
          if (value != CellState.empty && value != color) hostile++;
        }
      }
    }
    final edge = r == 0 || c == 0 || r == size - 1 || c == size - 1;
    return hostile <= (edge ? 0 : 1);
  }
}
