import 'package:flutter/material.dart';

/// Two related sections share a row when their content has enough space.
class AdaptiveCardPair extends StatelessWidget {
  final Widget first, second;
  final double breakpoint;
  final int firstFlex, secondFlex;
  const AdaptiveCardPair(
      {super.key,
      required this.first,
      required this.second,
      this.breakpoint = 600,
      this.firstFlex = 1,
      this.secondFlex = 1});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        if (bounds.maxWidth < breakpoint) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                first,
                const SizedBox(height: 16),
                second,
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: firstFlex, child: first),
          const SizedBox(width: 16),
          Expanded(flex: secondFlex, child: second),
        ]);
      });
}
