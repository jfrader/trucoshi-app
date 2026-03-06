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
  WsMsg({required this.type, this.data});

  final String type;
  final Map<String, Object?>? data;

  Map<String, Object?> toJson() => {
        'type': type,
        if (data != null) 'data': data,
      };

  static WsMsg fromJson(Map<String, Object?> json) {
    final rawData = json['data'];
    return WsMsg(
      type: json['type'] as String,
      data: rawData == null ? null : (rawData as Map).cast<String, Object?>(),
    );
  }

  // Common helpers
  static WsMsg ping({required int clientTimeMs}) => WsMsg(
        type: 'ping',
        data: {'client_time_ms': clientTimeMs},
      );

  static WsMsg lobbySnapshotGet() => WsMsg(
        type: 'lobby.snapshot.get',
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
    // IMPORTANT: if we send `options`, it must be a complete `MatchOptions` object
    // (all fields required by the v2 schema). We mirror backend defaults here.
    final shouldSendOptions =
        maxPlayers != null || matchPoints != null || flor != null || turnTimeMs != null;

    final options = <String, Object?>{
      if (shouldSendOptions) 'max_players': maxPlayers ?? 6,
      if (shouldSendOptions) 'flor': flor ?? true,
      if (shouldSendOptions) 'match_points': matchPoints ?? 9,
      if (shouldSendOptions) 'turn_time_ms': turnTimeMs ?? 30000,
    };

    return WsMsg(
      type: 'match.create',
      data: {
        'name': name,
        ...?(shouldSendOptions ? {'options': options} : null),
        ...?(team == null ? null : {'team': team}),
      },
    );
  }

  static WsMsg matchJoin({
    required String matchId,
    required String name,
    int? team,
  }) {
    return WsMsg(
      type: 'match.join',
      data: {
        'match_id': matchId,
        'name': name,
        ...?(team == null ? null : {'team': team}),
      },
    );
  }

  static WsMsg matchWatch({required String matchId}) => WsMsg(
        type: 'match.watch',
        data: {
          'match_id': matchId,
        },
      );

  static WsMsg matchReady({
    required String matchId,
    required bool ready,
  }) => WsMsg(
        type: 'match.ready',
        data: {
          'match_id': matchId,
          'ready': ready,
        },
      );

  static WsMsg matchStart({
    required String matchId,
  }) => WsMsg(
        type: 'match.start',
        data: {
          'match_id': matchId,
        },
      );

  static WsMsg matchLeave({required String matchId}) => WsMsg(
        type: 'match.leave',
        data: {
          'match_id': matchId,
        },
      );

  static WsMsg matchPause({required String matchId}) => WsMsg(
        type: 'match.pause',
        data: {
          'match_id': matchId,
        },
      );

  static WsMsg matchResume({required String matchId}) => WsMsg(
        type: 'match.resume',
        data: {
          'match_id': matchId,
        },
      );

  static WsMsg gameSnapshotGet({
    required String matchId,
  }) => WsMsg(
        type: 'game.snapshot.get',
        data: {
          'match_id': matchId,
        },
      );

  static WsMsg gamePlayCard({
    required String matchId,
    required int cardIdx,
  }) => WsMsg(
        type: 'game.play_card',
        data: {
          'match_id': matchId,
          'card_idx': cardIdx,
        },
      );

  static WsMsg gameSay({
    required String matchId,
    required String command,
  }) => WsMsg(
        type: 'game.say',
        data: {
          'match_id': matchId,
          'command': command,
        },
      );

  static WsMsg chatJoin({
    required String roomId,
  }) => WsMsg(
        type: 'chat.join',
        data: {
          'room_id': roomId,
        },
      );

  static WsMsg chatSay({
    required String roomId,
    required String content,
  }) => WsMsg(
        type: 'chat.say',
        data: {
          'room_id': roomId,
          'content': content,
        },
      );
}
