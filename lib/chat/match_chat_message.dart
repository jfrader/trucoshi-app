import 'package:flutter/foundation.dart';

/// Parsed chat message payload from WS v2 `chat.*` events.
@immutable
class MatchChatMessage {
  const MatchChatMessage({
    required this.id,
    required this.content,
    required this.system,
    required this.timestamp,
    required this.userName,
    this.seatIdx,
    this.teamIdx,
  });

  final String id;
  final String content;
  final bool system;
  final DateTime timestamp;
  final String userName;
  final int? seatIdx;
  final int? teamIdx;

  /// `null` when payload is missing required fields.
  static MatchChatMessage? fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final rawContent = json['content'] as String?;
    final system = json['system'] == true;
    final dateMs = (json['date_ms'] as num?)?.toInt();
    final userJson = (json['user'] as Map?)?.cast<String, Object?>();
    final userName = userJson == null ? null : userJson['name'] as String?;
    final seatIdx = (userJson?['seat_idx'] as num?)?.toInt();
    final teamIdx = (userJson?['team'] as num?)?.toInt();

    if (id == null || userName == null || dateMs == null) {
      return null;
    }

    return MatchChatMessage(
      id: id,
      content: (rawContent ?? '').trimRight(),
      system: system,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        dateMs,
        isUtc: true,
      ).toLocal(),
      userName: userName.trim().isEmpty ? 'Unknown' : userName.trim(),
      seatIdx: seatIdx,
      teamIdx: teamIdx,
    );
  }

  bool get isSpectator => seatIdx == null;

  String get seatLabel => isSpectator ? 'Spectator' : 'Seat $seatIdx';

  String get initials {
    final trimmed = userName.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }
}
