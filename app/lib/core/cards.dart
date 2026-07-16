/// Card encoding — exact mirror of `@goat/shared/cards.ts`.
/// A card is an int in [0, 35]: id = suit * 9 + rankIndex.
/// Rank order (low → high): 6 < 7 < 8 < 9 < J < Q < K < 10 < A.
library;

const suits = ['spades', 'clubs', 'diamonds', 'hearts'];
const suitSymbols = ['♠', '♣', '♦', '♥'];
const ranks = ['6', '7', '8', '9', 'J', 'Q', 'K', '10', 'A'];
const rankPoints = [0, 0, 0, 0, 2, 3, 4, 10, 11];

const deckSize = 36;
const handSize = 6;

/// Шоха — the 6 of clubs. Beats everything as a beating card.
const shoha = 9;

int suitOf(int card) => card ~/ 9;
int rankOf(int card) => card % 9;
int pointsOf(int card) => rankPoints[rankOf(card)];
bool isShoha(int card) => card == shoha;
bool isRed(int card) => suitOf(card) >= 2;

String cardName(int card) => '${ranks[rankOf(card)]}${suitSymbols[suitOf(card)]}';
String suitSymbol(int suit) => suitSymbols[suit];

int sumPoints(Iterable<int> cards) => cards.fold(0, (s, c) => s + pointsOf(c));
