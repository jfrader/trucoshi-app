String describeKickReason(String? reason) {
  switch (reason) {
    case 'owner_kick':
      return 'Removed by the match owner.';
    case 'disconnect_timeout':
      return 'Removed after disconnecting for too long.';
    case 'lobby_inactivity':
      return 'Removed after being inactive in the lobby.';
    case 'afk_sweep':
      return 'Removed by the inactivity sweep.';
    default:
      if (reason == null || reason.trim().isEmpty) {
        return 'Removed from the match.';
      }
      return 'Removed: $reason';
  }
}
