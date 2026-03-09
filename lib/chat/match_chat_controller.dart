import 'package:flutter/foundation.dart';

import 'match_chat_message.dart';

class MatchChatController extends ChangeNotifier {
  final List<MatchChatMessage> _messages = [];
  final Map<String, MatchChatMessage> _byId = <String, MatchChatMessage>{};
  bool _isReady = false;

  List<MatchChatMessage> get messages => List.unmodifiable(_messages);
  bool get isReady => _isReady;
  bool get isEmpty => _messages.isEmpty;

  void replaceAll(List<MatchChatMessage> next) {
    _messages
      ..clear()
      ..addAll(next);
    _byId
      ..clear()
      ..addEntries(next.map((m) => MapEntry(m.id, m)));
    _isReady = true;
    notifyListeners();
  }

  /// Returns true when the message is brand new (so UI can auto-scroll).
  bool append(MatchChatMessage message) {
    final existingIdx = _messages.indexWhere((m) => m.id == message.id);
    if (existingIdx != -1) {
      _messages[existingIdx] = message;
      _byId[message.id] = message;
      notifyListeners();
      return false;
    }

    _messages.add(message);
    _byId[message.id] = message;
    notifyListeners();
    return true;
  }

  void clear() {
    _messages.clear();
    _byId.clear();
    _isReady = false;
    notifyListeners();
  }
}
