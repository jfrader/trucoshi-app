import 'dart:convert';

/// Tiny helper for tolerant parsing.
///
/// We use this to be resilient to schema drift / malformed frames without
/// crashing the WS listener.
class WsParseResult<T> {
  const WsParseResult._(this.value, this.error);

  const WsParseResult.ok(T v) : this._(v, null);
  const WsParseResult.err(String e) : this._(null, e);

  final T? value;
  final String? error;

  bool get isOk => value != null;
}

/// WS protocol v2 frame envelope (client -> server).
///
/// Contract source of truth: `trucoshi-rs/schemas/ws/v2/in.json`.
class WsInFrame {
  WsInFrame({this.id, required this.msg});

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
  WsOutFrame({required this.v, this.id, required this.msg});

  final int v;
  final String? id;
  final WsMsg msg;

  /// Strict parser (throws on unexpected shape).
  static WsOutFrame fromJson(Map<String, Object?> json) {
    return WsOutFrame(
      v: json['v'] as int,
      id: json['id'] as String?,
      msg: WsMsg.fromJson((json['msg'] as Map).cast<String, Object?>()),
    );
  }

  /// Tolerant parser (never throws).
  static WsParseResult<WsOutFrame> parse(Object? decoded) {
    if (decoded is! Map) {
      return const WsParseResult.err('expected JSON object at top-level');
    }
    return parseJson(decoded.cast<String, Object?>());
  }

  /// Tolerant parser (never throws).
  static WsParseResult<WsOutFrame> parseJson(Map<String, Object?> json) {
    final rawV = json['v'];
    final v = switch (rawV) {
      int n => n,
      num n => n.toInt(),
      _ => null,
    };

    if (v == null) {
      return const WsParseResult.err('missing/invalid "v"');
    }

    final rawId = json['id'];
    final id = rawId == null ? null : (rawId is String ? rawId : null);

    if (rawId != null && id == null) {
      return const WsParseResult.err('invalid "id" (expected string)');
    }

    final rawMsg = json['msg'];
    if (rawMsg is! Map) {
      return const WsParseResult.err('missing/invalid "msg" (expected object)');
    }

    final msgRes = WsMsg.parseJson(rawMsg.cast<String, Object?>());
    final msg = msgRes.value;
    if (msg == null) {
      return WsParseResult.err(
        'invalid "msg": ${msgRes.error ?? 'unknown error'}',
      );
    }

    return WsParseResult.ok(WsOutFrame(v: v, id: id, msg: msg));
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

  /// Strict parser (throws on unexpected shape).
  static WsMsg fromJson(Map<String, Object?> json) {
    final rawData = json['data'];
    return WsMsg(
      type: json['type'] as String,
      data: rawData == null ? null : (rawData as Map).cast<String, Object?>(),
    );
  }

  /// Tolerant parser (never throws).
  static WsParseResult<WsMsg> parseJson(Map<String, Object?> json) {
    final rawType = json['type'];
    if (rawType is! String || rawType.isEmpty) {
      return const WsParseResult.err('missing/invalid "type"');
    }

    final rawData = json['data'];
    Map<String, Object?>? data;
    if (rawData == null) {
      data = null;
    } else if (rawData is Map) {
      data = rawData.cast<String, Object?>();
    } else {
      return const WsParseResult.err('invalid "data" (expected object)');
    }

    return WsParseResult.ok(WsMsg(type: rawType, data: data));
  }

  // Common helpers
  static WsMsg ping({required int clientTimeMs}) =>
      WsMsg(type: 'ping', data: {'client_time_ms': clientTimeMs});

  static WsMsg lobbySnapshotGet() => WsMsg(type: 'lobby.snapshot.get');

  static WsMsg meActiveMatchesGet() => WsMsg(type: 'me.active_matches.get');

  static WsMsg matchSnapshotGet({required String matchId}) =>
      WsMsg(type: 'match.snapshot.get', data: {'match_id': matchId});

  static WsMsg matchCreate({
    required String name,
    int? maxPlayers,
    int? matchPoints,
    int? faltaEnvido,
    bool? flor,
    int? turnTimeMs,
    int? abandonTimeMs,
    int? reconnectGraceMs,
    int? team,
  }) {
    // IMPORTANT: if we send `options`, it must be a complete `MatchOptions` object
    // (all fields required by the v2 schema). We mirror backend defaults here.
    final shouldSendOptions =
        maxPlayers != null ||
        matchPoints != null ||
        faltaEnvido != null ||
        flor != null ||
        turnTimeMs != null ||
        abandonTimeMs != null ||
        reconnectGraceMs != null;

    final options = <String, Object?>{
      if (shouldSendOptions) 'max_players': maxPlayers ?? 6,
      if (shouldSendOptions) 'flor': flor ?? true,
      if (shouldSendOptions) 'match_points': matchPoints ?? 9,
      if (shouldSendOptions) 'falta_envido': faltaEnvido ?? 2,
      if (shouldSendOptions) 'turn_time_ms': turnTimeMs ?? 30000,
      if (shouldSendOptions) 'abandon_time_ms': abandonTimeMs ?? 120000,
      if (shouldSendOptions) 'reconnect_grace_ms': reconnectGraceMs ?? 5000,
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

  static WsMsg matchKick({required String matchId, required int seatIdx}) {
    return WsMsg(
      type: 'match.kick',
      data: {'match_id': matchId, 'seat_idx': seatIdx},
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

  static WsMsg matchWatch({required String matchId}) =>
      WsMsg(type: 'match.watch', data: {'match_id': matchId});

  static WsMsg matchReady({required String matchId, required bool ready}) =>
      WsMsg(type: 'match.ready', data: {'match_id': matchId, 'ready': ready});

  static WsMsg matchStart({required String matchId}) =>
      WsMsg(type: 'match.start', data: {'match_id': matchId});

  static WsMsg matchLeave({required String matchId}) =>
      WsMsg(type: 'match.leave', data: {'match_id': matchId});

  static WsMsg matchOptionsSet({
    required String matchId,
    required int maxPlayers,
    required int matchPoints,
    required bool flor,
    required int turnTimeMs,
    required int abandonTimeMs,
    required int reconnectGraceMs,
    required int faltaEnvido,
  }) {
    return WsMsg(
      type: 'match.options.set',
      data: {
        'match_id': matchId,
        'options': {
          'max_players': maxPlayers,
          'match_points': matchPoints,
          'flor': flor,
          'turn_time_ms': turnTimeMs,
          'abandon_time_ms': abandonTimeMs,
          'reconnect_grace_ms': reconnectGraceMs,
          'falta_envido': faltaEnvido,
        },
      },
    );
  }

  static WsMsg matchRematch({required String matchId}) =>
      WsMsg(type: 'match.rematch', data: {'match_id': matchId});

  static WsMsg matchPause({required String matchId}) =>
      WsMsg(type: 'match.pause', data: {'match_id': matchId});

  static WsMsg matchPauseVote({
    required String matchId,
    required bool accept,
  }) =>
      WsMsg(
        type: 'match.pause.vote',
        data: {'match_id': matchId, 'accept': accept},
      );

  static WsMsg matchResume({required String matchId}) =>
      WsMsg(type: 'match.resume', data: {'match_id': matchId});

  static WsMsg gameSnapshotGet({required String matchId}) =>
      WsMsg(type: 'game.snapshot.get', data: {'match_id': matchId});

  static WsMsg gamePlayCard({required String matchId, required int cardIdx}) =>
      WsMsg(
        type: 'game.play_card',
        data: {'match_id': matchId, 'card_idx': cardIdx},
      );

  static WsMsg gameSay({required String matchId, required String command}) =>
      WsMsg(type: 'game.say', data: {'match_id': matchId, 'command': command});

  static WsMsg chatJoin({required String roomId}) =>
      WsMsg(type: 'chat.join', data: {'room_id': roomId});

  static WsMsg chatSay({required String roomId, required String content}) =>
      WsMsg(type: 'chat.say', data: {'room_id': roomId, 'content': content});
}
