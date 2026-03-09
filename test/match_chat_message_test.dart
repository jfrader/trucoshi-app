import 'package:flutter_test/flutter_test.dart';
import 'package:trucoshi_app/chat/match_chat_message.dart';

void main() {
  test('fromJson parses minimal payload', () {
    final msg = MatchChatMessage.fromJson({
      'id': '123',
      'content': 'hola',
      'system': false,
      'date_ms': 1700000000000,
      'user': {'name': 'Fran', 'seat_idx': 1, 'team': 0},
    });

    expect(msg, isNotNull);
    expect(msg!.id, '123');
    expect(msg.userName, 'Fran');
    expect(msg.seatIdx, 1);
    expect(msg.teamIdx, 0);
    expect(msg.isSpectator, isFalse);
    expect(msg.seatLabel, 'Seat 1');
  });

  test('fromJson returns null when required fields are missing', () {
    final missingId = MatchChatMessage.fromJson({
      'content': 'hola',
      'date_ms': 1,
      'user': {'name': 'Fran'},
    });
    expect(missingId, isNull);

    final missingUser = MatchChatMessage.fromJson({
      'id': 'x',
      'content': 'hola',
      'date_ms': 1,
    });
    expect(missingUser, isNull);
  });
}
