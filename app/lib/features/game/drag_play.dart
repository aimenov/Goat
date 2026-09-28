/// Drag-to-play support widgets for the table screen.
library;

import 'package:flutter/material.dart';

import '../../shared/cards/card_face.dart';
import '../../shared/theme/cosmetic_styles.dart';
import '../../shared/theme/tokens.dart';

/// Floating stack shown under the pointer while hand cards are dragged:
/// up to three offset [CardFace]s (onTap == null / unselected keeps their
/// static fast path) — or [CardBack]s when the drop discards face-down —
/// plus an «×n» brass badge when the payload is larger.
/// No GlobalKeys — the feedback lives in the app overlay and must never
/// collide with the anchored table subtrees.
class DragCardsFeedback extends StatelessWidget {
  const DragCardsFeedback({
    super.key,
    required this.cards,
    this.cardHeight = 92,
    this.faceDown = false,
    this.backStyle = CardBackStyle.classic,
  });

  /// The cards that would be played by this drop, first card on top.
  final List<int> cards;
  final double cardHeight;

  /// Discard drags ride face-down: the throw goes втёмную.
  final bool faceDown;
  final CardBackStyle backStyle;

  @override
  Widget build(BuildContext context) {
    const offX = 16.0;
    const offY = 10.0;
    final cardW = cardHeight * cardAspect;
    final shown = cards.length > 3 ? cards.sublist(0, 3) : cards;
    return IgnorePointer(
      child: RepaintBoundary(
        // pointerDragAnchorStrategy pins the feedback's top-left to the
        // finger; shift so the lead card rides centered under it instead.
        child: Transform.translate(
          offset: Offset(-cardW / 2, -cardHeight / 2),
          // Transparent Material: the badge Text renders in the overlay,
          // outside any Material ancestor.
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: cardW + (shown.length - 1) * offX,
              height: cardHeight + (shown.length - 1) * offY,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: i * offX,
                      top: i * offY,
                      child: faceDown
                          ? CardBack(height: cardHeight, style: backStyle)
                          : CardFace(card: shown[i], height: cardHeight),
                    ),
                  if (cards.length > shown.length)
                    Positioned(
                      top: -8,
                      right: -12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Tokens.gold400,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Tokens.gold600, width: 1),
                        ),
                        child: Text(
                          '×${cards.length}',
                          style: Tokens.numeric.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Tokens.onGold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
