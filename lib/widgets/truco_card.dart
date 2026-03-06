import 'package:flutter/material.dart';

/// Renders a Truco card image from assets.
///
/// Server payloads typically encode cards as short codes like `1o`, `7e`, etc.
/// We map those to `assets/cards/<deck>/<code>.png`.
class TrucoCardImage extends StatelessWidget {
  const TrucoCardImage(
    this.card, {
    super.key,
    this.deck = 'default',
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.elevation = 1,
  });

  final String card;
  final String deck;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizeCardCode(card);
    final assetPath = _assetPath(deck: deck, code: normalized);

    return Material(
      elevation: elevation,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        assetPath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stack) {
          final scheme = Theme.of(context).colorScheme;
          return Container(
            width: width,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: borderRadius,
              border: Border.all(color: scheme.outlineVariant),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              normalized.isEmpty ? '?' : normalized,
              style: const TextStyle(fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    );
  }
}

String _normalizeCardCode(String raw) {
  final s = raw.trim().toLowerCase();

  // If server ever sends a richer string like `card:1o`, keep only alnum.
  return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _assetPath({required String deck, required String code}) {
  if (code.startsWith('assets/')) return code;
  return 'assets/cards/$deck/$code.png';
}
