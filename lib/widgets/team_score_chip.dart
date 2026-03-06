import 'package:flutter/material.dart';

/// Displays a team's current score with optional highlight/winner styles.
class TeamScoreChip extends StatelessWidget {
  const TeamScoreChip({
    super.key,
    required this.teamIdx,
    this.points,
    this.highlight = false,
    this.winner = false,
  });

  final int teamIdx;
  final int? points;
  final bool highlight;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final base = teamIdx == 0 ? scheme.primary : scheme.tertiary;

    final bg = winner
        ? base.withOpacity(0.25)
        : highlight
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest;

    final border = winner
        ? Border.all(color: base, width: 2)
        : highlight
            ? Border.all(color: scheme.secondary, width: 2)
            : Border.all(color: scheme.outlineVariant);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: border,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              winner ? 'Team $teamIdx • WIN' : 'Team $teamIdx',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          Text(
            (points ?? 0).toString(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: base,
            ),
          ),
        ],
      ),
    );
  }
}
