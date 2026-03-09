import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../services/stats_repository.dart';

class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({
    super.key,
    required this.auth,
    required this.userId,
    this.stats,
  });

  final AuthService auth;
  final int userId;
  final StatsRepository? stats;

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  late final StatsRepository _stats;
  late final bool _ownsStats;

  PlayerProfile? _profile;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

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

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      if (reset) {
        _profile = null;
        _error = null;
      }
      _loading = true;
    });

    try {
      final profile = await _stats.fetchPlayerProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
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
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final profile = _profile;
    if (profile == null || !profile.hasMore || _loadingMore) return;
    setState(() {
      _loadingMore = true;
    });

    try {
      final next = await _stats.fetchPlayerProfile(
        widget.userId,
        offset: profile.nextOffset,
      );
      if (!mounted) return;
      setState(() {
        _profile = PlayerProfile(
          user: profile.user,
          totals: profile.totals,
          recentMatches: [...profile.recentMatches, ...next.recentMatches],
          nextOffset: next.nextOffset,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load more: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
      });
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _outcomeLabel(PlayerMatchOutcome outcome) {
    switch (outcome) {
      case PlayerMatchOutcome.win:
        return 'Win';
      case PlayerMatchOutcome.loss:
        return 'Loss';
      case PlayerMatchOutcome.inProgress:
        return 'In progress';
    }
  }

  Color _outcomeColor(PlayerMatchOutcome outcome, BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    switch (outcome) {
      case PlayerMatchOutcome.win:
        return colors.primary;
      case PlayerMatchOutcome.loss:
        return colors.error;
      case PlayerMatchOutcome.inProgress:
        return colors.tertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(
        title: Text('Player ${widget.userId}'),
        actions: [
          IconButton(
            tooltip: 'Leaderboard',
            onPressed: () => context.go('/stats/leaderboard'),
            icon: const Icon(Icons.leaderboard),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: profile == null && _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (profile != null) ...[
                    _buildUserCard(profile.user),
                    const SizedBox(height: 12),
                    _buildTotalsCard(profile.totals),
                    const SizedBox(height: 16),
                    Text(
                      'Recent matches',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (profile.recentMatches.isEmpty)
                      const Text('No matches recorded yet.'),
                    for (final match in profile.recentMatches)
                      Card(
                        child: ListTile(
                          title: Text('Match ${match.displayMatchId}'),
                          subtitle: Text(
                            'Started: ${_formatDate(match.createdAt)}\nFinished: ${_formatDate(match.finishedAt)}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _outcomeLabel(match.outcome),
                                style: TextStyle(
                                  color: _outcomeColor(match.outcome, context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _pointsLabel(match),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          onTap: () => context.go(
                            '/history/match/${match.displayMatchId}',
                          ),
                        ),
                      ),
                    if (profile.hasMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: OutlinedButton.icon(
                          onPressed: _loadingMore ? null : _loadMore,
                          icon: _loadingMore
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more),
                          label: const Text('Load more matches'),
                        ),
                      ),
                  ] else if (!_loading)
                    const Text('Player profile not available.'),
                ],
              ),
      ),
    );
  }

  Widget _buildUserCard(PlayerProfileUser user) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase()),
        ),
        title: Text(user.name),
        subtitle: Text('ID ${user.id}\nJoined: ${_formatDate(user.createdAt)}'),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildTotalsCard(PlayerProfileTotals totals) {
    final stats = [
      _TotalsEntry('Played', totals.matchesPlayed.toString()),
      _TotalsEntry('Finished', totals.matchesFinished.toString()),
      _TotalsEntry('Wins', totals.matchesWon.toString()),
      _TotalsEntry('Win rate', '${(totals.winRate * 100).toStringAsFixed(1)}%'),
      _TotalsEntry('Points for', totals.pointsFor.toString()),
      _TotalsEntry('Points against', totals.pointsAgainst.toString()),
      _TotalsEntry('Diff', totals.pointsDiff.toString()),
      _TotalsEntry('Last played', _formatDate(totals.lastPlayedAt)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final entry in stats)
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _pointsLabel(PlayerMatchSummary match) {
    final forPts = match.pointsFor;
    final against = match.pointsAgainst;
    if (forPts == null || against == null) return 'Points —';
    final diff = forPts - against;
    final diffLabel = diff > 0 ? '+$diff' : diff.toString();
    return '$forPts-$against ($diffLabel)';
  }
}

class _TotalsEntry {
  const _TotalsEntry(this.label, this.value);

  final String label;
  final String value;
}
