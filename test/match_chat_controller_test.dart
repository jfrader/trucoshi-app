import 'package:flutter_test/flutter_test.dart';
import 'package:trucoshi_app/chat/match_chat_controller.dart';
import 'package:trucoshi_app/chat/match_chat_message.dart';

MatchChatMessage _msg(
  String id, {
  int? seatIdx,
  int? teamIdx,
  bool system = false,
}) {
  return MatchChatMessage(
    id: id,
    content: 'hello $id',
    system: system,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    userName: 'Player $id',
    seatIdx: seatIdx,
    teamIdx: teamIdx,
  );
}

void main() {
  test('replaceAll marks controller ready and exposes messages in order', () {
    final controller = MatchChatController();
    expect(controller.isReady, isFalse);

    controller.replaceAll([_msg('a'), _msg('b')]);

    expect(controller.isReady, isTrue);
    expect(controller.messages.map((m) => m.id), ['a', 'b']);
  });

  test('append returns true only for brand new messages', () {
    final controller = MatchChatController();
    controller.replaceAll([_msg('existing')]);

    final isNew = controller.append(_msg('next'));
    expect(isNew, isTrue);
    expect(controller.messages.map((m) => m.id), ['existing', 'next']);

    final replaced = controller.append(_msg('existing', system: true));
    expect(replaced, isFalse);
    expect(controller.messages.length, 2);
    expect(controller.messages.first.system, isTrue);
  });

  test('clear empties controller and marks it not ready', () {
    final controller = MatchChatController();
    controller.replaceAll([_msg('seed')]);

    controller.clear();

    expect(controller.isReady, isFalse);
    expect(controller.messages, isEmpty);
  });
}
