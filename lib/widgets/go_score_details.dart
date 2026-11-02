import 'package:flutter/material.dart';
import '../services/go_engine.dart';

/// The same area-scoring explanation for local and server-owned matches.
class GoScoreDetails extends StatelessWidget {
  final GoScore score;
  const GoScoreDetails({super.key, required this.score});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '黑 ${score.black.toStringAsFixed(1)} · 白 ${score.white.toStringAsFixed(1)}',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
            '黑方：活子 ${score.blackStones} + 围空 ${score.blackTerritory.length} = ${score.black.toStringAsFixed(1)}'),
        Text(
            '白方：活子 ${score.whiteStones} + 围空 ${score.whiteTerritory.length} + 贴目 ${score.komi.toStringAsFixed(1)} = ${score.white.toStringAsFixed(1)}'),
        Text(
            '死子：黑 ${score.blackDead} · 白 ${score.whiteDead}；中立空点 ${score.neutralPoints}'),
        const SizedBox(height: 8),
        Text('当前数子：${score.result}'),
        const SizedBox(height: 8),
        const Text(
            '面积计分：活子与围空各计 1 点，提子不额外加分。黑/白小方块表示归属，未标记的空点为中立。未收官或死活未核对时，结果仅供参考。'),
      ]);
}
