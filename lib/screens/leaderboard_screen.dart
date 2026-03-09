import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../services/stats_repository.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, required this.auth, this.stats});

  final AuthService auth;
  final StatsRepository? stats;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late final StatsRepository _stats;
  late final bool _ownsStats;

  final _entries = <LeaderboardEntry>[];

  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int? _nextOffset;
  int _minFinished = 5;

  static const _minFinishedOptions = [1, 5, 10, 20];

  @override
  void initState() {
    super.initState();
    _ownsStats = widget.stats == null;
    _stats = widget.stats ?? HttpStatsRepository(auth: widget.auth);
    _load(reset: true);
  }

  @override
  void dispose() {
    if (_ownsStats) {
      _stats.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool reset = false, bool append = false}) async {
    if (!mounted) return;

    if (append) {
      if (_loadingMore || _nextOffset == null) return;
      setState(() {
        _loadingMore = true;
      });
    } else {
      if (_loading) return;
      setState(() {
        _loading = true;
        if (reset) {
          _entries.clear();
          _nextOffset = null;
          _error = null;
        }
      });
    }

    final offset = append ? _nextOffset : null;

    try {
      final page = await _stats.fetchLeaderboard(
        minFinished: _minFinished,
        offset: offset,
      );

      if (!mounted) return;
      setState(() {
        if (!append) {
          _entries
            ..clear()
            ..addAll(page.entries);
        } else {
          _entries.addAll(page.entries);
        }
        _nextOffset = page.nextOffset;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        if (append) {
          _loadingMore = false;
        } else {
          _loading = false;
        }
      });
    }
  }

  void _setMinFinished(int value) {
    if (value == _minFinished) return;
    setState(() {
      _minFinished = value;
    });
    _load(reset: true);
  }

  String _formatWinRate(double rate) {
    final pct = (rate * 100).toStringAsFixed(1);
    return '$pct%';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _entries.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFilters(context),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_entries.isEmpty && !_loading)
                    const Text('No players found for this filter.'),
                  for (final entry in _entries)
                    _LeaderboardEntryCard(
                      entry: entry,
                      onTap: () => context.go('/stats/player/${entry.userId}'),
                      winRateLabel: _formatWinRate(entry.winRate),
                    ),
                  if (_nextOffset != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: OutlinedButton.icon(
                        onPressed: _loadingMore
                            ? null
                            : () => _load(append: true),
                        icon: _loadingMore
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more),
                        label: const Text('Load more'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Minimum finished matches',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final option in _minFinishedOptions)
                  ChoiceChip(
                    label: Text('$option+'),
                    selected: _minFinished == option,
                    onSelected: (_) => _setMinFinished(option),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardEntryCard extends StatelessWidget {
  const _LeaderboardEntryCard({
    required this.entry,
    required this.onTap,
    required this.winRateLabel,
  });

  final LeaderboardEntry entry;
  final VoidCallback onTap;
  final String winRateLabel;

  @override
  Widget build(BuildContext context) {
    final title = entry.name;
    final subtitle = 'Rank ${entry.rank} • ${entry.matchesFinished} finished';

    final diff = entry.pointsDiff;
    final diffLabel = diff == 0
        ? 'Diff 0'
        : diff > 0
        ? '+$diff'
        : diff.toString();

    final lastPlayed = entry.lastPlayedAt;
    final lastLabel = lastPlayed == null
        ? 'Last played: —'
        : 'Last played: ${_relativeTime(lastPlayed)}';

    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text('$subtitle\n$lastLabel'),
        isThreeLine: true,
        leading: CircleAvatar(
          child: Text(entry.name.isEmpty ? '?' : entry.name[0].toUpperCase()),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Win $winRateLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              'Points $diffLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  String _relativeTime(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inDays >= 1) {
      return '${diff.inDays}d ago';
    }
    if (diff.inHours >= 1) {
      return '${diff.inHours}h ago';
    }
    if (diff.inMinutes >= 1) {
      return '${diff.inMinutes}m ago';
    }
    return 'Just now';
  }
}
