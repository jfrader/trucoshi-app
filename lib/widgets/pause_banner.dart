import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pause_models.dart';
import 'status_chip.dart';

class PauseRequestBanner extends StatelessWidget {
  const PauseRequestBanner({
    super.key,
    required this.requestedByLabel,
    required this.awaitingTeamLabel,
    required this.awaitingSeats,
    required this.expiresAtMs,
    required this.isAwaitingMember,
    required this.canVote,
    required this.hasAccepted,
    required this.voteSubmitting,
    required this.onAccept,
    required this.onDecline,
  });

  final String requestedByLabel;
  final String awaitingTeamLabel;
  final List<PauseAwaitingSeat> awaitingSeats;
  final int expiresAtMs;
  final bool isAwaitingMember;
  final bool canVote;
  final bool hasAccepted;
  final bool voteSubmitting;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final acceptedCount = awaitingSeats.where((seat) => seat.accepted).length;
    final totalAwaiting = awaitingSeats.length;
    final canInteract = isAwaitingMember && canVote && !hasAccepted;
    final requesterLabel = requestedByLabel.trim().isEmpty
        ? 'Unknown player'
        : requestedByLabel.trim();
    final teamLabel = awaitingTeamLabel.trim().isEmpty
        ? 'their team'
        : awaitingTeamLabel.trim();

    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pause requested by $requesterLabel',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Waiting for $teamLabel to accept'
              ' ($acceptedCount/$totalAwaiting).',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            CountdownText(
              targetEpochMs: expiresAtMs,
              prefix: 'Request expires in ',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: awaitingSeats.map((seat) {
                return StatusChip(
                  icon: seat.accepted
                      ? Icons.check_circle
                      : Icons.hourglass_bottom,
                  label:
                      '${seat.name}${seat.isMe ? ' (You)' : ''} – Seat ${seat.seatIdx}' +
                      (seat.accepted ? '' : ' (pending)'),
                  tone: seat.accepted ? scheme.tertiary : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            if (isAwaitingMember)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canInteract && !voteSubmitting
                          ? onAccept
                          : null,
                      icon: voteSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(hasAccepted ? 'Accepted' : 'Accept pause'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canInteract && !voteSubmitting
                          ? onDecline
                          : null,
                      icon: const Icon(Icons.close),
                      label: const Text('Decline'),
                    ),
                  ),
                ],
              )
            else
              Text(
                'Waiting for $teamLabel to respond…',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class PendingUnpauseBanner extends StatelessWidget {
  const PendingUnpauseBanner({super.key, required this.resumeAtMs});

  final int resumeAtMs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resume countdown in progress',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            CountdownText(targetEpochMs: resumeAtMs, prefix: 'Resuming in '),
          ],
        ),
      ),
    );
  }
}

class CountdownText extends StatefulWidget {
  const CountdownText({
    super.key,
    required this.targetEpochMs,
    this.prefix,
    this.completeLabel = '0s',
  });

  final int targetEpochMs;
  final String? prefix;
  final String completeLabel;

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = _computeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _computeRemaining();
      if (mounted) {
        setState(() {
          _remaining = next;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant CountdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetEpochMs != widget.targetEpochMs) {
      setState(() {
        _remaining = _computeRemaining();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _computeRemaining() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final diffMs = widget.targetEpochMs - nowMs;
    if (diffMs <= 0) return Duration.zero;
    return Duration(milliseconds: diffMs);
  }

  @override
  Widget build(BuildContext context) {
    final label = _remaining == Duration.zero
        ? widget.completeLabel
        : _formatDuration(_remaining);
    return Text('${widget.prefix ?? ''}$label');
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0) {
      if (seconds == 0) {
        return '${minutes}m';
      }
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}
