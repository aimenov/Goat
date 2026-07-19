/// Maps server [TableEvent]s (and optimistic local plays) to fire-and-forget
/// effects on the [FlightLayer]. Everything here is decorative: any missing
/// anchor falls back to a sensible point, any failure is swallowed, and game
/// state is never touched.
library;

import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/cards.dart';
import '../../../core/game/game_controller.dart';
import '../../../core/game/models.dart';
import '../../../core/services/sound.dart';
import '../../../shared/cards/card_face.dart';
import '../../../shared/theme/cosmetic_styles.dart';
import 'flight_layer.dart';
import 'flight_math.dart';
import 'table_anchors.dart';

class TableFx {
  TableFx({required this.anchors, required this.layerKey, required this.sound});

  final TableAnchors anchors;
  final GlobalKey<FlightLayerState> layerKey;
  final SoundService sound;

  /// Called when a trick has been vacuumed toward its winner (badge pop).
  void Function(int winnerSeat)? onTrickTaken;

  /// Called when a new deal starts (felt light-sweep re-key).
  VoidCallback? onDealStarted;

  /// Equipped card-back skin for the face-down flights (draws, discards,
  /// vacuum). Set from the TableScreen build; cosmetics cannot change
  /// mid-game (the shop is unreachable from the table), so it never goes
  /// stale between builds.
  CardBackStyle cardBackStyle = CardBackStyle.classic;

  Random _rng = Random(1);
  final StaggerScheduler _stagger = StaggerScheduler();
  final Map<String, DateTime> _suppressUntil = {};

  static const _cardH = 72.0;

  /// Web gets a slightly looser deal stagger and shorter deal flights: fewer
  /// simultaneous flights raster per frame during the ~24-card burst.
  static const _dealGap = Duration(milliseconds: kIsWeb ? 95 : 70);

  // ---------------------------------------------------------------- events

  /// Entry point for server events. Runs after the frame so the freshly
  /// committed state is laid out; failures are swallowed (decorative only).
  void handleEvent(TableEvent event, GameUiState state) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      try {
        _dispatch(event, state);
      } catch (_) {
        // Flights are fire-and-forget; never let them break the table.
      }
    });
  }

  void _dispatch(TableEvent e, GameUiState s) {
    final layer = layerKey.currentState;
    if (layer == null || !layer.mounted) return;
    switch (e.type) {
      case 'dealStarted':
        _rng = Random(
          ((e.data['dealIndex'] as num?)?.toInt() ?? 0) * 7919 + 17,
        );
        _stagger.reset();
        sound.resetDrawWindow();
        sound.drawBatch(); // riffle for the deal-out
        onDealStarted?.call();

      case 'yourDraw':
        _flyMyDraws(layer, asIntList(e.data['cards']));

      case 'cardDrawn':
        final seat = (e.data['seat'] as num?)?.toInt();
        if (seat != null && seat != s.mySeat) _flyDraw(layer, seat, s);

      case 'trumpRevealed':
        final card = (e.data['card'] as num?)?.toInt();
        if (card != null) {
          // The 3D flip in _TrumpFx completes at t=0.34 of 1500 ms.
          sound.play(Sfx.cardFlip);
          sound.playDelayed(Sfx.trumpChime, const Duration(milliseconds: 510));
          layer.playTrumpReveal(card: card, dock: _stockPos(layer));
        }

      case 'led':
        final seat = (e.data['seat'] as num?)?.toInt();
        if (seat == null) return;
        if (seat == s.mySeat && _consumeSuppression('led')) return;
        _flyLead(layer, seat, asIntList(e.data['cards']), s);

      case 'beaten':
        final seat = (e.data['seat'] as num?)?.toInt();
        if (seat == null) return;
        if (seat == s.mySeat && _consumeSuppression('beaten')) return;
        final cards = [
          for (final p in (e.data['pairs'] as List? ?? const []))
            (asMap(p)['card'] as num).toInt(),
        ];
        _flyBeat(layer, seat, cards, s);

      case 'discarded':
        final seat = (e.data['seat'] as num?)?.toInt();
        if (seat == null) return;
        if (seat == s.mySeat && _consumeSuppression('discarded')) return;
        _flyDiscard(layer, seat, (e.data['count'] as num?)?.toInt() ?? 1, s);

      case 'trickEnded':
        final winner = (e.data['winner'] as num?)?.toInt();
        if (winner == null) return;
        _flyVacuum(
          layer,
          winner,
          (e.data['cardCount'] as num?)?.toInt() ?? 4,
          s,
        );
        onTrickTaken?.call(winner);

      case 'gameEnded':
        HapticFeedback.heavyImpact();
        // unknown seat (snapshot race / old server): don't guess the outcome
        if (s.mySeat < 0) return;
        sound.play(
          asIntList(e.data['goats']).contains(s.mySeat)
              ? Sfx.goatMoan
              : Sfx.winFanfare,
        );
    }
  }

  // ------------------------------------------------------ optimistic plays

  /// My lead starts flying immediately on tap-confirm; the echoing server
  /// event is suppressed so the flight doesn't play twice.
  void playMyLead(List<int> cards) {
    final layer = _liveLayer();
    if (layer == null) return;
    _suppressNext('led');
    _leadFlights(layer, _handPos(layer), cards);
  }

  void playMyBeat(List<int> cards) {
    final layer = _liveLayer();
    if (layer == null) return;
    _suppressNext('beaten');
    HapticFeedback.mediumImpact();
    _beatFlights(layer, _handPos(layer), cards);
  }

  void playMyDiscard(int count) {
    final layer = _liveLayer();
    if (layer == null) return;
    _suppressNext('discarded');
    _discardFlights(layer, _handPos(layer), count);
  }

  // ------------------------------------------------------- choreographies

  void _flyMyDraws(FlightLayerState layer, List<int> cards) {
    if (cards.isNotEmpty) sound.drawBatch(); // coalesced riffle, never slides
    final from = _stockPos(layer);
    final to = _handPos(layer);
    for (final card in cards) {
      layer.flyCard(
        from: from,
        to: to + Offset(jitterAngle(_rng, 30), 0),
        card: CardFace(card: card, height: _cardH),
        width: _cardH * cardAspect,
        height: _cardH,
        style: FlightStyle.deal,
        // Only the base differs per platform; the single nextInt(60) draw
        // stays in place so the RNG sequence (and thus every later jitter)
        // is identical across platforms for a given deal seed.
        duration: Duration(milliseconds: (kIsWeb ? 300 : 420) + _rng.nextInt(60)),
        delay: _stagger.reserve(_dealGap),
        bend: jitterAngle(_rng, 0.16),
        endRotation: jitterAngle(_rng, 0.10),
      );
    }
  }

  void _flyDraw(FlightLayerState layer, int seat, GameUiState s) {
    sound.drawBatch(); // coalesced riffle, never slides
    layer.flyCard(
      from: _stockPos(layer),
      to: _seatPos(layer, seat, s),
      card: CardBack(height: _cardH, style: cardBackStyle),
      width: _cardH * cardAspect,
      height: _cardH,
      style: FlightStyle.deal,
      // Base differs per platform; the nextInt(60) draw stays in place to
      // preserve the RNG draw order (see _flyMyDraws).
      duration: Duration(milliseconds: (kIsWeb ? 300 : 400) + _rng.nextInt(60)),
      delay: _stagger.reserve(_dealGap),
      bend: jitterAngle(_rng, 0.16),
      endRotation: jitterAngle(_rng, 0.14),
    );
  }

  void _flyLead(
    FlightLayerState layer,
    int seat,
    List<int> cards,
    GameUiState s,
  ) {
    _leadFlights(layer, _seatPos(layer, seat, s), cards);
  }

  void _leadFlights(FlightLayerState layer, Offset from, List<int> cards) {
    final center = _trickPos(layer);
    // Spec §1: slides/snaps for the first 3 cards only; big sets riffle once.
    final riffleOnly = cards.length > 6;
    if (riffleOnly) sound.play(Sfx.dealRiffle);
    for (var i = 0; i < cards.length; i++) {
      final delay = Duration(milliseconds: 70 * i);
      final duration = Duration(milliseconds: 300 + _rng.nextInt(50));
      if (!riffleOnly && i < 3) {
        sound.playDelayed(Sfx.cardSlide, delay);
        sound.playDelayed(Sfx.cardSnap, delay + duration);
      }
      layer.flyCard(
        from: from,
        to: center + Offset((i - (cards.length - 1) / 2) * 28, 0),
        card: CardFace(card: cards[i], height: _cardH),
        width: _cardH * cardAspect,
        height: _cardH,
        style: FlightStyle.play,
        duration: duration,
        delay: delay,
        bend: jitterAngle(_rng, 0.14),
        endRotation: jitterAngle(_rng, 0.07),
      );
    }
  }

  void _flyBeat(
    FlightLayerState layer,
    int seat,
    List<int> cards,
    GameUiState s,
  ) {
    HapticFeedback.mediumImpact();
    _beatFlights(layer, _seatPos(layer, seat, s), cards);
  }

  void _beatFlights(FlightLayerState layer, Offset from, List<int> cards) {
    final center = _trickPos(layer);
    // Spec §1: slides/snaps for the first 3 cards only; big sets riffle once.
    final riffleOnly = cards.length > 6;
    if (riffleOnly) sound.play(Sfx.dealRiffle);
    for (var i = 0; i < cards.length; i++) {
      final to = center + Offset((i - (cards.length - 1) / 2) * 28, 14);
      if (isShoha(cards[i])) {
        // shoha_impact is played by the FlightLayer, frame-exact with the slam.
        layer.playShoha(from: from, to: to, card: cards[i]);
      } else {
        final delay = Duration(milliseconds: 80 * i);
        final duration = Duration(milliseconds: 320 + _rng.nextInt(50));
        if (!riffleOnly && i < 3) {
          sound.playDelayed(Sfx.cardSlide, delay);
          sound.playDelayed(Sfx.cardSnap, delay + duration, gain: 1.25);
        }
        layer.flyCard(
          from: from,
          to: to,
          card: CardFace(card: cards[i], height: _cardH),
          width: _cardH * cardAspect,
          height: _cardH,
          style: FlightStyle.slam,
          duration: duration,
          delay: delay,
          bend: jitterAngle(_rng, 0.12),
          endRotation: jitterAngle(_rng, 0.08),
        );
      }
    }
  }

  void _flyDiscard(FlightLayerState layer, int seat, int count, GameUiState s) {
    _discardFlights(layer, _seatPos(layer, seat, s), count);
  }

  void _discardFlights(FlightLayerState layer, Offset from, int count) {
    // One flip per discard event, timed to the mid-flight face-down flip
    // (raw t=0.38 of a ~330 ms discard flight).
    sound.playDelayed(Sfx.cardFlip, const Duration(milliseconds: 125));
    final to = _discardPos(layer);
    for (var i = 0; i < count; i++) {
      layer.flyCard(
        from: from,
        to: to + Offset(jitterAngle(_rng, 10), jitterAngle(_rng, 5)),
        card: CardBack(height: _cardH, style: cardBackStyle),
        width: _cardH * cardAspect,
        height: _cardH,
        style: FlightStyle.discard,
        duration: Duration(milliseconds: 330 + _rng.nextInt(50)),
        delay: Duration(milliseconds: 60 * i),
        bend: jitterAngle(_rng, 0.14),
        endRotation: jitterAngle(_rng, 0.30),
        flip: true,
      );
    }
  }

  void _flyVacuum(
    FlightLayerState layer,
    int winner,
    int cardCount,
    GameUiState s,
  ) {
    final center = _trickPos(layer);
    final to = winner == s.mySeat
        ? _local(layer, anchors.wonChip, _handPos(layer))
        : _seatPos(layer, winner, s);
    final n = min(cardCount, 10);
    // Exactly one thud per trick, at the last vacuum card's landing:
    // delay 26·(n-1) + duration 330 + 14·(n-1) = 330 + 40·(n-1) ms.
    sound.playDelayed(
      Sfx.stackThud,
      Duration(milliseconds: 330 + 40 * (n - 1)),
    );
    for (var i = 0; i < n; i++) {
      layer.flyCard(
        from: center + Offset(jitterAngle(_rng, 70), jitterAngle(_rng, 34)),
        to: to,
        card: CardBack(height: 46, style: cardBackStyle),
        width: 46 * cardAspect,
        height: 46,
        style: FlightStyle.vacuum,
        duration: Duration(milliseconds: 330 + i * 14),
        delay: Duration(milliseconds: 26 * i),
        bend: jitterAngle(_rng, 0.10),
        startRotation: jitterAngle(_rng, 0.35),
      );
    }
  }

  // ---------------------------------------------------------------- anchors

  FlightLayerState? _liveLayer() {
    final layer = layerKey.currentState;
    return layer != null && layer.mounted ? layer : null;
  }

  Offset _local(FlightLayerState layer, GlobalKey key, Offset fallback) {
    final global = anchors.globalCenterOf(key);
    return global == null ? fallback : layer.globalToLocal(global);
  }

  Offset _stockPos(FlightLayerState layer) {
    final size = layer.layerSize;
    return _local(layer, anchors.stock, Offset(max(size.width - 70, 0), 46));
  }

  Offset _trickPos(FlightLayerState layer) {
    final size = layer.layerSize;
    return _local(layer, anchors.trick, size.center(Offset.zero));
  }

  Offset _handPos(FlightLayerState layer) {
    final size = layer.layerSize;
    return _local(
      layer,
      anchors.hand,
      Offset(size.width / 2, max(size.height - 120, 0)),
    );
  }

  Offset _discardPos(FlightLayerState layer) =>
      _local(layer, anchors.discard, _trickPos(layer) + const Offset(0, 76));

  Offset _seatPos(FlightLayerState layer, int seat, GameUiState s) {
    if (seat == s.mySeat) return _handPos(layer);
    final size = layer.layerSize;
    return _local(layer, anchors.seat(seat), Offset(size.width / 2, 120));
  }

  // ----------------------------------------------------------- suppression

  /// Swallow the next echoed event of [type] for my own optimistic play.
  /// Expires after 4 s so a rejected intent can never permanently eat a
  /// future animation.
  void _suppressNext(String type) =>
      _suppressUntil[type] = DateTime.now().add(const Duration(seconds: 4));

  bool _consumeSuppression(String type) {
    final until = _suppressUntil.remove(type);
    return until != null && DateTime.now().isBefore(until);
  }
}
