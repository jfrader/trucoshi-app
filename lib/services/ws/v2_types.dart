import 'dart:convert';

/// WS protocol v2 frame envelope (client -> server).
///
/// Contract source of truth: `trucoshi-rs/schemas/ws/v2/in.json`.
class WsInFrame {
  WsInFrame({
    this.id,
    required this.msg,
  });

  final int v = 2;
  final String? id;
  final WsMsg msg;

  Map<String, Object?> toJson() => {
        'v': v,
        if (id != null) 'id': id,
        'msg': msg.toJson(),
      };

  String encode() => jsonEncode(toJson());
}

/// WS protocol v2 frame envelope (server -> client).
///
/// Contract source of truth: `trucoshi-rs/schemas/ws/v2/out.json`.
class WsOutFrame {
  WsOutFrame({
    required this.v,
    this.id,
    required this.msg,
  });

  final int v;
  final String? id;
  final WsMsg msg;

  static WsOutFrame fromJson(Map<String, Object?> json) {
    return WsOutFrame(
      v: json['v'] as int,
      id: json['id'] as String?,
      msg: WsMsg.fromJson(json['msg'] as Map<String, Object?>),
    );
  }
}

/// `{ type: string, data: object }`
///
/// We keep [data] as a raw JSON map for now, and introduce typed payloads later.
class WsMsg {
  WsMsg({required this.type, required this.data});

  final String type;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'type': type,
        'data': data,
      };

  static WsMsg fromJson(Map<String, Object?> json) {
    return WsMsg(
      type: json['type'] as String,
      data: (json['data'] as Map).cast<String, Object?>(),
    );
  }

  // Common helpers
  static WsMsg ping({required int clientTimeMs}) => WsMsg(
        type: 'ping',
        data: {'client_time_ms': clientTimeMs},
      );

  static WsMsg lobbySnapshotGet() => WsMsg(
        type: 'lobby.snapshot.get',
        data: const {},
      );

  static WsMsg matchSnapshotGet({required String matchId}) => WsMsg(
        type: 'match.snapshot.get',
        data: {'match_id': matchId},
      );

  static WsMsg matchCreate({
    required String name,
    int? maxPlayers,
    int? matchPoints,
    bool? flor,
    int? turnTimeMs,
    int? team,
  }) {
    final options = <String, Object?>{};
    if (maxPlayers != null) options['max_players'] = maxPlayers;
    if (matchPoints != null) options['match_points'] = matchPoints;
    if (flor != null) options['flor'] = flor;
    if (turnTimeMs != null) options['turn_time_ms'] = turnTimeMs;

    return WsMsg(
      type: 'match.create',
      data: {
        'name': name,
        ...?(options.isEmpty ? null : {'options': options}),
        ...?(team == null ? null : {'team': team}),
      },
    );
  }
}
