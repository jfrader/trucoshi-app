class PauseRequestView {
  const PauseRequestView({
    required this.requestedBySeatIdx,
    required this.requestedByTeam,
    required this.awaitingTeam,
    required this.expiresAtMs,
    required this.acceptedSeatIdxs,
  });

  final int? requestedBySeatIdx;
  final int? requestedByTeam;
  final int awaitingTeam;
  final int expiresAtMs;
  final List<int> acceptedSeatIdxs;
}

class PendingUnpauseView {
  const PendingUnpauseView({required this.resumeAtMs});

  final int resumeAtMs;
}

class PauseAwaitingSeat {
  const PauseAwaitingSeat({
    required this.seatIdx,
    required this.name,
    required this.accepted,
    this.isMe = false,
  });

  final int seatIdx;
  final String name;
  final bool accepted;
  final bool isMe;
}

PauseRequestView? readPauseRequest(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['pause_request'];
  if (raw is! Map) return null;

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  final requestedBySeatIdx = _readInt(raw['requested_by_seat_idx']);
  final requestedByTeam = _readInt(raw['requested_by_team']);
  final awaitingTeam = _readInt(raw['awaiting_team']);
  final expiresAtMs = _readInt(raw['expires_at_ms']);
  final accepted = <int>[];

  final acceptedRaw = raw['accepted_seat_idxs'];
  if (acceptedRaw is List) {
    for (final entry in acceptedRaw) {
      final parsed = _readInt(entry);
      if (parsed != null) accepted.add(parsed);
    }
  }

  if (awaitingTeam == null || expiresAtMs == null) {
    return null;
  }

  return PauseRequestView(
    requestedBySeatIdx: requestedBySeatIdx,
    requestedByTeam: requestedByTeam,
    awaitingTeam: awaitingTeam,
    expiresAtMs: expiresAtMs,
    acceptedSeatIdxs: accepted,
  );
}

PendingUnpauseView? readPendingUnpause(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['pending_unpause'];
  if (raw is! Map) return null;

  int? resumeAtMs;
  final value = raw['resume_at_ms'];
  if (value is int) {
    resumeAtMs = value;
  } else if (value is num) {
    resumeAtMs = value.toInt();
  } else if (value is String) {
    resumeAtMs = int.tryParse(value);
  }

  if (resumeAtMs == null) return null;
  return PendingUnpauseView(resumeAtMs: resumeAtMs);
}

int? parseTeamIdx(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<PauseAwaitingSeat> buildPauseAwaitingSeats({
  required PauseRequestView request,
  required List<Map<String, Object?>> players,
  required int? meSeatIdx,
}) {
  final awaiting = <PauseAwaitingSeat>[];
  for (var i = 0; i < players.length; i++) {
    final team = parseTeamIdx(players[i]['team']);
    if (team != request.awaitingTeam) continue;

    final name = _displayNameForSeat(players[i]['name'], i);
    final accepted = request.acceptedSeatIdxs.contains(i);
    awaiting.add(
      PauseAwaitingSeat(
        seatIdx: i,
        name: name,
        accepted: accepted,
        isMe: meSeatIdx == i,
      ),
    );
  }
  return awaiting;
}

String describePauseRequester(
  PauseRequestView request,
  List<Map<String, Object?>> players,
) {
  final seatIdx = request.requestedBySeatIdx;
  if (seatIdx != null && seatIdx >= 0 && seatIdx < players.length) {
    final name = players[seatIdx]['name'];
    if (name is String) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'Seat $seatIdx';
  }

  final fallbackSeat = seatIdx != null ? 'Seat $seatIdx' : 'match owner';
  final team = request.requestedByTeam;
  if (team != null) {
    return '$fallbackSeat (team $team)';
  }
  return fallbackSeat;
}

String _displayNameForSeat(Object? rawName, int seatIdx) {
  if (rawName is String) {
    final trimmed = rawName.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return 'Seat $seatIdx';
}
