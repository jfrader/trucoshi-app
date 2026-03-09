import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/stats_repository.dart';

class MatchHistoryScreen extends StatefulWidget {
  const MatchHistoryScreen({
    super.key,
    required this.auth,
    required this.matchId,
    this.stats,
  });

  final AuthService auth;
  final String matchId;
  final StatsRepository? stats;

  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  late final StatsRepository _stats;
  late final bool _ownsStats;

  MatchHistory? _history;
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
        _history = null;
        _error = null;
      }
      _loading = true;
    });

    try {
      final history = await _stats.fetchMatchHistory(widget.matchId);
      if (!mounted) return;
      setState(() {
        _history = history;
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
    final history = _history;
    if (history == null || !history.hasMoreEvents || _loadingMore) return;
    setState(() {
      _loadingMore = true;
    });

    try {
      final next = await _stats.fetchMatchHistory(
        widget.matchId,
        afterSeq: history.nextAfterSeq,
      );
      if (!mounted) return;
      setState(() {
        _history = MatchHistory(
          id: next.id,
          wsMatchId: next.wsMatchId ?? history.wsMatchId,
          createdAt: next.createdAt ?? history.createdAt,
          finishedAt: next.finishedAt ?? history.finishedAt,
          serverVersion: next.serverVersion ?? history.serverVersion,
          protocolVersion: next.protocolVersion ?? history.protocolVersion,
          rngSeed: next.rngSeed ?? history.rngSeed,
          options: history.options,
          players: history.players,
          events: [...history.events, ...next.events],
          nextAfterSeq: next.nextAfterSeq,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load more events: $e')));
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
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _prettyJson(Map<String, Object?> data) {
    if (data.isEmpty) return '{}';
    const encoder = JsonEncoder.withIndent('  ');
    try {
      return encoder.convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;

    return Scaffold(
      appBar: AppBar(title: Text('Match ${widget.matchId}')),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: history == null && _loading
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
                  if (history != null) ...[
                    _buildSummaryCard(history),
                    const SizedBox(height: 12),
                    _buildPlayersCard(history),
                    const SizedBox(height: 12),
                    Text(
                      'Events',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (history.events.isEmpty)
                      const Text('No events recorded for this match.'),
                    for (final event in history.events)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${event.seq} • ${event.type}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Created: ${_formatDate(event.createdAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 12,
                                children: [
                                  if (event.actorSeatIdx != null)
                                    Text('Seat ${event.actorSeatIdx}'),
                                  if (event.actorUserId != null)
                                    Text('User ${event.actorUserId}'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _prettyJson(event.data),
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (history.hasMoreEvents)
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
                          label: const Text('Load more events'),
                        ),
                      ),
                  ] else if (!_loading)
                    const Text('Match not found.'),
                ],
              ),
      ),
    );
  }

  Widget _buildSummaryCard(MatchHistory history) {
    final entries = [
      _SummaryEntry('Match ID', history.id.toString()),
      _SummaryEntry('WS match ID', history.wsMatchId ?? '—'),
      _SummaryEntry('Created at', _formatDate(history.createdAt)),
      _SummaryEntry('Finished at', _formatDate(history.finishedAt)),
      _SummaryEntry('Server version', history.serverVersion ?? '—'),
      _SummaryEntry('Protocol', history.protocolVersion?.toString() ?? '—'),
      _SummaryEntry('RNG seed', history.rngSeed?.toString() ?? '—'),
    ];

    final options = history.options;
    final optionsText = options.isEmpty
        ? '{}'
        : const JsonEncoder.withIndent('  ').convert(options);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final entry in entries)
                  SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.label,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(entry.value),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Match options',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              optionsText,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayersCard(MatchHistory history) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Players', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (history.players.isEmpty)
              const Text('No players recorded.')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: history.players.length,
                itemBuilder: (context, index) {
                  final player = history.players[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(player.displayName ?? 'Seat ${player.seatIdx}'),
                    subtitle: Text(
                      'Seat ${player.seatIdx} • Team ${player.teamIdx} • User ${player.userId ?? '-'}',
                    ),
                    trailing: Text(_formatDate(player.createdAt)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryEntry {
  const _SummaryEntry(this.label, this.value);

  final String label;
  final String value;
}
