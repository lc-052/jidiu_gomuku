import 'package:flutter/material.dart';

/// Shared card shell for independently reusable page sections.
class SectionCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  const SectionCard(
      {super.key,
      this.title,
      this.subtitle,
      this.trailing,
      required this.child});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) ...[
              Row(children: [
                Expanded(
                    child: Text(title!,
                        style: Theme.of(context).textTheme.titleMedium)),
                if (trailing != null) trailing!
              ]),
              if (subtitle != null)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(subtitle!,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant))),
              const SizedBox(height: 16),
            ],
            child,
          ]),
        ),
      );
}
