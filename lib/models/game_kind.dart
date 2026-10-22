enum GameKind {
  gomoku('五子棋', '连成五子，落定胜负'),
  go('围棋', '一子一地，步步经营');

  final String label;
  final String description;
  const GameKind(this.label, this.description);
}
