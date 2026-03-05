import 'package:flutter/material.dart';

/// Table screen skeleton.
///
/// For now it takes a mock list of [playerNames]. In protocol v2, seating is
/// implied by `players[]` ordering. This widget rotates seating so the local
/// player renders at the bottom.
class TableScreen extends StatelessWidget {
  const TableScreen({
    super.key,
    required this.localPlayerId,
    required this.playerNames,
  });

  final String localPlayerId;
  final List<String> playerNames;

  @override
  Widget build(BuildContext context) {
    final rotated = _rotateToBottom(playerNames, localPlayerId);

    return Scaffold(
      appBar: AppBar(title: const Text('Table')),
      body: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          final positions = _seatPositions(rotated.length, size);

          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Text('TABLE')),
                ),
              ),
              for (var i = 0; i < rotated.length; i++)
                Positioned(
                  left: positions[i].dx,
                  top: positions[i].dy,
                  child: _Seat(name: rotated[i], isMe: rotated[i] == localPlayerId),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.name, required this.isMe});

  final String name;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: isMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.secondary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Text(name.substring(0, 1).toUpperCase()),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          style: TextStyle(
            fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

List<String> _rotateToBottom(List<String> players, String localPlayerId) {
  if (players.isEmpty) return players;

  final idx = players.indexOf(localPlayerId);
  if (idx < 0) return players;

  // Define that index 0 in the rotated list is "bottom".
  return [...players.skip(idx), ...players.take(idx)];
}

/// Returns top-left coordinates for each seat, where seat[0] is bottom.
///
/// Supports 2/4/6 players.
List<Offset> _seatPositions(int n, Size size) {
  final w = size.width;
  final h = size.height;

  // Center points for the seat widgets.
  final bottom = Offset(w * 0.5, h * 0.82);
  final top = Offset(w * 0.5, h * 0.10);
  final left = Offset(w * 0.08, h * 0.46);
  final right = Offset(w * 0.92, h * 0.46);

  final topLeft = Offset(w * 0.18, h * 0.16);
  final topRight = Offset(w * 0.82, h * 0.16);
  final bottomLeft = Offset(w * 0.18, h * 0.76);
  final bottomRight = Offset(w * 0.82, h * 0.76);

  // Seat widget approximate size, used to shift from center->topLeft.
  const seatSize = Size(90, 80);
  Offset tl(Offset center) =>
      Offset(center.dx - seatSize.width / 2, center.dy - seatSize.height / 2);

  switch (n) {
    case 2:
      return [tl(bottom), tl(top)];
    case 4:
      // Bottom (me), left, top, right (clockwise).
      return [tl(bottom), tl(left), tl(top), tl(right)];
    case 6:
      // Bottom (me), bottom-left, top-left, top, top-right, bottom-right.
      return [
        tl(bottom),
        tl(bottomLeft),
        tl(topLeft),
        tl(top),
        tl(topRight),
        tl(bottomRight),
      ];
    default:
      // Fallback: place all at bottom.
      return List.filled(n, tl(bottom));
  }
}
