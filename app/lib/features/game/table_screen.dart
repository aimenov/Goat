/// The game table — portrait phone layout driven by [gameControllerProvider].
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cards.dart';
import '../../core/game/game_controller.dart';
import '../../core/game/models.dart';
import '../../core/services/sound.dart';
import '../../core/session.dart';
import '../../shared/cards/card_face.dart';
import '../../shared/cards/suit_paths.dart';
import '../../shared/felt/felt_background.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/brass_chip.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/gold_frame.dart';
import '../achievements/achievements.dart';
import 'anim/confetti.dart';
import 'anim/felt_sweep.dart';
import 'anim/flight_layer.dart';
import 'anim/motion_widgets.dart';
import 'anim/table_anchors.dart';
import 'anim/table_fx.dart';
import 'selection.dart';

const _reactionIds = ['thumbs_up', 'laugh', 'shock', 'goat', 'fire', 'cry'];
const _reactionEmojis = {
  'thumbs_up': '👍',
  'laugh': '😂',
  'shock': '😱',
  'goat': '🐐',
  'fire': '🔥',
  'cry': '😭',
};

class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key});

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  // Hand selection (lead / discard modes).
  final Set<int> _selected = {};

  // Beat mode: target card -> assigned hand card.
  final Map<int, int> _beatAssignment = {};
  int? _beatTarget;
  bool _beatMode = false;

  // Reaction bubbles: seat -> emoji glyph.
  final Map<int, String> _bubbles = {};
  final Map<int, Timer> _bubbleTimers = {};

  int _deadlineAnchor = 0;

  bool _showDealOverlay = false;
  Timer? _dealOverlayTimer;
  bool _rematchVoted = false;
  bool _myReadyLocal = false;
  bool _reconnectBusy = false;

  StreamSubscription<TableEvent>? _eventsSub;
  StreamSubscription<String>? _rejectionsSub;
  ProviderSubscription<GameUiState>? _stateSub;

  // Animation pass: anchors + flight overlay + event choreography.
  final TableAnchors _anchors = TableAnchors();
  final GlobalKey<FlightLayerState> _flightKey = GlobalKey<FlightLayerState>();
  late final TableFx _fx;
  late final SoundService _sound;

  // Won-pile badge pops: seat -> generation counter (re-keys a PunchIn).
  final Map<int, int> _wonPop = {};
  final Map<int, Timer> _wonPopTimers = {};

  // Felt light-sweep on deal start: re-keyed one-shot.
  int _sweepGen = 0;

  // Achievement unlock banners: shown one at a time, queued otherwise.
  final List<AchievementDef> _achQueue = [];
  AchievementDef? _achBanner;
  bool _achVisible = false;
  Timer? _achTimer;

  @override
  void initState() {
    super.initState();
    _sound = ref.read(soundServiceProvider);
    _fx = TableFx(anchors: _anchors, layerKey: _flightKey, sound: _sound)
      ..onTrickTaken = _onTrickTaken
      ..onDealStarted = _onDealStarted;
    final controller = ref.read(gameControllerProvider.notifier);
    _eventsSub = controller.tableEvents.listen(_onTableEvent);
    _rejectionsSub = controller.rejections.listen(_onRejection);
    _stateSub = ref.listenManual(gameControllerProvider, _onGameState);
  }

  @override
  void dispose() {
    _dealOverlayTimer?.cancel();
    for (final t in _bubbleTimers.values) {
      t.cancel();
    }
    for (final t in _wonPopTimers.values) {
      t.cancel();
    }
    _achTimer?.cancel();
    _eventsSub?.cancel();
    _rejectionsSub?.cancel();
    _stateSub?.close();
    // a scheduled thud/chime must not play on the next screen
    _sound.cancelDelayed();
    super.dispose();
  }

  /// Pops the winner's won-pile badge once the vacuum flights have landed.
  void _onTrickTaken(int seat) {
    _wonPopTimers[seat]?.cancel();
    _wonPopTimers[seat] = Timer(const Duration(milliseconds: 520), () {
      if (mounted) setState(() => _wonPop[seat] = (_wonPop[seat] ?? 0) + 1);
    });
  }

  /// Replays the felt light-sweep at each deal start.
  void _onDealStarted() {
    if (mounted) setState(() => _sweepGen++);
  }

  // ----------------------------------------------------------- listeners

  void _onGameState(GameUiState? previous, GameUiState next) {
    if (!mounted) return;
    if (next.isMyTurn &&
        previous?.isMyTurn != true &&
        next.roomPhase == RoomPhase.playing) {
      _sound.play(Sfx.myTurnDing); // 1500 ms cooldown guards resync flapping
    }
    setState(() {
      if (!identical(previous?.legal, next.legal)) {
        _selected.clear();
        _beatAssignment.clear();
        final legal = next.legal;
        _beatMode = legal != null && legal.kind == 'respond' && legal.canBeat;
        _beatTarget = _beatMode ? legal?.beatMatrix.keys.firstOrNull : null;
      }
      if (next.deadline != (previous?.deadline ?? 0) && next.deadline > 0) {
        _deadlineAnchor = DateTime.now().millisecondsSinceEpoch;
      }
      if (next.lastDealResults != null &&
          !identical(previous?.lastDealResults, next.lastDealResults) &&
          next.roomPhase != RoomPhase.gameOver) {
        _showDealOverlay = true;
        _dealOverlayTimer?.cancel();
        _dealOverlayTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _showDealOverlay = false);
        });
      }
      if (next.roomPhase == RoomPhase.gameOver &&
          previous?.roomPhase != RoomPhase.gameOver) {
        _rematchVoted = false;
        _showDealOverlay = false;
      }
    });
  }

  void _onTableEvent(TableEvent event) {
    if (!mounted) return;
    if (event.type == 'achievementUnlocked') {
      final def = achievementById('${event.data['id']}');
      if (def != null) {
        _achQueue.add(def);
        if (_achBanner == null) _showNextAchievement();
      }
      return;
    }
    if (event.type != 'reaction') {
      // Fire-and-forget flights and flourishes; never blocks state updates.
      _fx.handleEvent(event, ref.read(gameControllerProvider));
      return;
    }
    final seat = (event.data['seat'] as num?)?.toInt();
    final glyph = _reactionEmojis['${event.data['emoji']}'];
    if (seat == null || glyph == null) return;
    _sound.play(Sfx.reactionPop); // 300 ms global cooldown absorbs spam
    setState(() => _bubbles[seat] = glyph);
    _bubbleTimers[seat]?.cancel();
    _bubbleTimers[seat] = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _bubbles.remove(seat));
    });
  }

  /// Pops the next queued unlock: slide in, hold, slide out, repeat.
  void _showNextAchievement() {
    if (_achQueue.isEmpty) return;
    final def = _achQueue.removeAt(0);
    HapticFeedback.mediumImpact();
    _sound.play(Sfx.achievementBell);
    setState(() {
      _achBanner = def;
      _achVisible = true;
    });
    _achTimer?.cancel();
    _achTimer = Timer(const Duration(milliseconds: 3150), () {
      if (!mounted) return;
      setState(() => _achVisible = false);
      _achTimer = Timer(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() => _achBanner = null);
        _showNextAchievement();
      });
    });
  }

  void _onRejection(String _) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Tokens.dangerDeep,
        content: Text('Так ходить нельзя'),
      ),
    );
  }

  // ----------------------------------------------------------- helpers

  String _nick(GameUiState state, int seat) {
    for (final s in state.seats) {
      if (s.seat == seat) return s.nickname;
    }
    for (final s in state.lobbySeats) {
      if (s.seat == seat) return s.nickname;
    }
    return 'Игрок ${seat + 1}';
  }

  String _initial(String nickname) =>
      nickname.isEmpty ? '?' : nickname.characters.first.toUpperCase();

  bool _beatModeActive(GameUiState state) {
    final legal = state.legal;
    return state.isMyTurn &&
        legal != null &&
        legal.canBeat &&
        _beatMode &&
        (legal.kind == 'respond' || legal.kind == 'leaderDecision');
  }

  int? _firstUnassignedTarget(LegalActions legal) {
    for (final t in legal.beatMatrix.keys) {
      if (!_beatAssignment.containsKey(t)) return t;
    }
    return null;
  }

  /// Beat chains per lead card: [lead, beat1, beat2, ...].
  List<List<int>> _chains(TrickState trick) {
    if (trick.sets.isEmpty) return const [];
    final chains = [
      for (final c in trick.sets.first.cards) [c],
    ];
    for (final set in trick.sets.skip(1)) {
      for (final chain in chains) {
        final next = set.pairing[chain.last];
        if (next != null) chain.add(next);
      }
    }
    return chains;
  }

  // ----------------------------------------------------------- intents

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Покинуть стол?'),
        content: const Text('Вы выйдете из текущей игры.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (leave == true) await _leaveNow();
  }

  Future<void> _leaveNow() async {
    await ref.read(roomSessionProvider.notifier).leave();
    if (mounted) context.go('/lobby');
  }

  void _onTargetTap(GameUiState state, int target) {
    final legal = state.legal;
    if (!_beatModeActive(state) || legal == null) return;
    if (!legal.beatMatrix.containsKey(target)) return;
    _sound.play(Sfx.tapSelect);
    setState(() {
      if (_beatAssignment.containsKey(target)) {
        _beatAssignment.remove(target);
        _beatTarget = target;
      } else {
        _beatTarget = _beatTarget == target ? null : target;
      }
    });
  }

  void _onHandTap(GameUiState state, int card) {
    final legal = state.legal;
    if (!state.isMyTurn || legal == null) return;
    HapticFeedback.selectionClick();
    _sound.play(Sfx.tapSelect);
    setState(() {
      if (_beatModeActive(state)) {
        // Tapping an assigned card takes it back.
        for (final entry in _beatAssignment.entries) {
          if (entry.value == card) {
            _beatAssignment.remove(entry.key);
            _beatTarget = entry.key;
            return;
          }
        }
        final target = _beatTarget;
        if (target == null) return;
        final options = legal.beatMatrix[target] ?? const <int>[];
        if (!options.contains(card)) return;
        _beatAssignment[target] = card;
        _beatTarget = _firstUnassignedTarget(legal);
      } else if (legal.kind == 'lead' ||
          (legal.kind == 'respond' && !_beatMode)) {
        if (!_selected.remove(card)) _selected.add(card);
      }
    });
  }

  void _autoAssign(LegalActions legal) {
    final pairing = autoPairing(legal.beatMatrix);
    if (pairing == null) return;
    setState(() {
      _beatAssignment
        ..clear()
        ..addAll(pairing);
      _beatTarget = null;
    });
  }

  void _sendBeat(GameController controller) {
    _sound.play(Sfx.buttonPress);
    _fx.playMyBeat(_beatAssignment.values.toList()); // optimistic flight
    controller.beat(Map<int, int>.of(_beatAssignment));
    setState(() {
      _beatAssignment.clear();
      _beatTarget = null;
      _beatMode = false;
    });
  }

  // ----------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);
    return Scaffold(
      backgroundColor: Colors.transparent,
      // The game surface is not selectable (matters for web/desktop).
      body: SelectionContainer.disabled(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: FeltBackground(lightCenter: Alignment(0, -0.1)),
            ),
            if (_sweepGen > 0)
              Positioned.fill(
                child: FeltSweep(key: ValueKey('sweep-$_sweepGen')),
              ),
            SafeArea(
              child: Column(
                children: [
                  _topBar(state),
                  _opponentsArea(state),
                  Expanded(
                    child: KeyedSubtree(
                      key: _anchors.trick,
                      child: _centerArea(state),
                    ),
                  ),
                  if (state.roomPhase == RoomPhase.playing) _timerStrip(state),
                  _myArea(state),
                  _actionBar(state, controller),
                  _reactionBar(state, controller),
                ],
              ),
            ),
            Positioned.fill(child: FlightLayer(key: _flightKey, sound: _sound)),
            if (state.roomPhase == RoomPhase.connecting) _connectingOverlay(),
            if (state.roomPhase == RoomPhase.lobby)
              _lobbyOverlay(state, controller),
            if (_showDealOverlay &&
                state.lastDealResults != null &&
                state.roomPhase != RoomPhase.gameOver)
              _dealOverlay(state),
            if (state.roomPhase == RoomPhase.gameOver)
              _gameOverOverlay(state, controller),
            if (state.roomPhase == RoomPhase.reconnecting) _reconnectOverlay(),
            _achievementBanner(),
          ],
        ),
      ),
    );
  }

  /// Golden banner that slides down from the top on `achievementUnlocked`.
  /// Always in the tree (parked off-screen) so the entry slide animates.
  Widget _achievementBanner() {
    final def = _achBanner;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: AnimatedSlide(
          offset: _achVisible && def != null
              ? Offset.zero
              : const Offset(0, -2),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: def == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Tokens.gold200, Tokens.gold500],
                      ),
                      borderRadius: BorderRadius.circular(Tokens.r14),
                      border: Border.all(color: Tokens.gold600, width: 1),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Text('🏆', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Достижение: ${def.title}!',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Tokens.onGold,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(def.emoji, style: const TextStyle(fontSize: 24)),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- top bar

  Widget _topBar(GameUiState state) {
    final title = switch (state.roomPhase) {
      RoomPhase.playing => 'Раздача ${state.dealIndex + 1}',
      RoomPhase.gameOver => 'Игра окончена',
      RoomPhase.reconnecting => 'Переподключение',
      _ => 'Козёл',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout),
            onPressed: _confirmLeave,
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: Tokens.serifFamily,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Tokens.gold200,
              ),
            ),
          ),
          if (state.roomPhase == RoomPhase.playing) ...[
            // Trump plaque: stock/trump cluster inside a double gold hairline.
            // The Row keeps `key: _anchors.stock` so flight anchors don't move.
            Container(
              decoration: BoxDecoration(
                color: Tokens.felt900.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(Tokens.r10),
                border: Border.all(
                  color: Tokens.gold400.withValues(alpha: 0.7),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Tokens.r10 - 2),
                  border: Border.all(
                    color: Tokens.gold600.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  key: _anchors.stock,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.trumpCard != null) ...[
                      CardFace(
                        card: state.trumpCard!,
                        height: 36,
                        trumpStyle: true,
                      ),
                      const SizedBox(width: 6),
                    ],
                    SuitIcon(suit: state.trumpSuit, size: 16),
                    const SizedBox(width: 8),
                    BrassChip(text: 'В колоде: ${state.stockCount}'),
                  ],
                ),
              ),
            ),
            if (state.multiplier > 1) ...[
              const SizedBox(width: 8),
              PunchIn(
                key: ValueKey('top-mult-${state.multiplier}'),
                child: BrassChip(
                  text: '×${state.multiplier}',
                  danger: state.multiplier >= 3,
                ),
              ),
            ],
            const SizedBox(width: 8),
          ],
          // Quick mute; long-press opens the volume sheet. No tooltip here:
          // IconButton.tooltip installs its own long-press recognizer that
          // would win the gesture arena and make the sheet unreachable.
          GestureDetector(
            onLongPress: _showVolumeSheet,
            child: IconButton(
              icon: Icon(
                _sound.muted ? Icons.volume_off : Icons.volume_up,
                color: Tokens.gold300,
              ),
              onPressed: () => setState(_sound.toggleMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// Minimal casino-styled volume sheet: mute toggle + gold slider.
  void _showVolumeSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.r20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Звук', style: Tokens.titleSerif),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Звук',
                      icon: Icon(
                        _sound.muted ? Icons.volume_off : Icons.volume_up,
                        color: Tokens.gold300,
                      ),
                      onPressed: () {
                        _sound.toggleMuted();
                        setSheetState(() {});
                        if (mounted) setState(() {});
                      },
                    ),
                    const Text(
                      'Громкость',
                      style: TextStyle(color: Tokens.textSecondary),
                    ),
                    Expanded(
                      child: Slider(
                        value: _sound.volume,
                        activeColor: Tokens.gold300,
                        onChanged: (v) {
                          _sound.volume = v;
                          setSheetState(() {});
                        },
                        // Audible level check at the chosen volume.
                        onChangeEnd: (_) => _sound.play(Sfx.buttonPress),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- opponents

  Widget _opponentsArea(GameUiState state) {
    if (state.playerCount <= 1 || state.mySeat < 0 || state.seats.isEmpty) {
      return const SizedBox.shrink();
    }
    final others = <SeatState>[];
    for (var i = 1; i < state.playerCount; i++) {
      final seat = (state.mySeat + i) % state.playerCount;
      for (final s in state.seats) {
        if (s.seat == seat) others.add(s);
      }
    }
    final rows = <List<SeatState>>[];
    for (var i = 0; i < others.length; i += 3) {
      rows.add(others.sublist(i, min(i + 3, others.length)));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final s in row) Flexible(child: _opponentTile(state, s)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _opponentTile(GameUiState state, SeatState seat) {
    final isTurn =
        state.roomPhase == RoomPhase.playing && state.trick?.turn == seat.seat;
    final bubble = _bubbles[seat.seat];
    return Stack(
      key: _anchors.seat(seat.seat),
      clipBehavior: Clip.none,
      children: [
        PulseGlow(
          active: isTurn,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(maxWidth: 120),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Tokens.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isTurn ? Tokens.gold300 : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              isTurn ? Tokens.gold300 : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Tokens.felt600,
                        child: Text(
                          _initial(seat.nickname),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Tokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        seat.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Tokens.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: seat.connected ? Tokens.success : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                AnimatedScoreChip(
                  prefix: 'Очки: ',
                  value: seat.score,
                  fontSize: 10,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _miniHandFan(seat.handCount),
                    const SizedBox(width: 8),
                    _wonChip(seat.wonCount, _wonPop[seat.seat] ?? 0),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (bubble != null)
          Positioned(
            top: -20,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Tokens.felt900.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(bubble, style: const TextStyle(fontSize: 22)),
            ),
          ),
      ],
    );
  }

  /// Mini fanned stack of card backs with an always-visible count badge.
  Widget _miniHandFan(int count) {
    final shown = count.clamp(0, 4);
    return SizedBox(
      width: 54,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (shown == 0)
            Positioned(
              left: 8,
              top: 2,
              child: Container(
                width: 21,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Tokens.gold600.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          for (var i = 0; i < shown; i++)
            Positioned(
              left: i * 8.0,
              top: 3,
              child: Transform.rotate(
                angle: (i - (shown - 1) / 2) * 0.10,
                child: const CardBack(height: 30),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Tokens.gold400,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '$count',
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
    );
  }

  Widget _wonChip(int count, int pop) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BrassChip.decoration(),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.layers, size: 12, color: Tokens.gold300),
        const SizedBox(width: 2),
        PunchIn(
          key: ValueKey('won-pop-$pop'),
          child: Text(
            '$count',
            style: Tokens.numeric.copyWith(
              fontSize: 11,
              color: Tokens.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );

  // ----------------------------------------------------------- center

  Widget _centerArea(GameUiState state) {
    final trick = state.trick;
    if (state.roomPhase != RoomPhase.playing ||
        trick == null ||
        trick.sets.isEmpty) {
      final turn = trick?.turn ?? -1;
      return Center(
        child: Text(
          turn >= 0 ? 'Ходит ${_nick(state, turn)}…' : 'Ждём…',
          style: const TextStyle(
            color: Tokens.textFaint,
            fontSize: 15,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    final chains = _chains(trick);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final chain in chains) _chainWidget(state, chain),
                ],
              ),
            ),
          ),
        ),
        if (trick.discards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 14,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < trick.discards.length; i++)
                  _discardStack(trick.discards[i], i),
              ],
            ),
          ),
        // Zero-height landing anchor for face-down discard flights.
        SizedBox(key: _anchors.discard, height: 0, width: double.infinity),
      ],
    );
  }

  Widget _chainWidget(GameUiState state, List<int> chain) {
    const cardH = 64.0;
    const offY = 24.0;
    const offX = 6.0;
    final cardW = cardH * cardAspect;
    final legal = state.legal;
    final beatActive = _beatModeActive(state);
    final target = chain.last;
    final isTargetable =
        beatActive && legal != null && legal.beatMatrix.containsKey(target);
    final assigned = _beatAssignment[target];
    final levels = chain.length + (assigned != null ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        width: cardW + (levels - 1) * offX,
        height: cardH + (levels - 1) * offY,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < chain.length; i++)
              Positioned(
                left: i * offX,
                top: i * offY,
                child: Container(
                  decoration: (i == chain.length - 1 && isTargetable)
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(cardH * 0.09),
                          boxShadow: [
                            BoxShadow(
                              color: Tokens.gold300.withValues(alpha: 0.55),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        )
                      : null,
                  child: CardFace(
                    card: chain[i],
                    height: cardH,
                    selected: i == chain.length - 1 && _beatTarget == chain[i],
                    onTap: i == chain.length - 1
                        ? () => _onTargetTap(state, chain[i])
                        : null,
                  ),
                ),
              ),
            if (assigned != null)
              Positioned(
                left: chain.length * offX,
                top: chain.length * offY,
                child: Opacity(
                  opacity: 0.85,
                  child: CardFace(
                    card: assigned,
                    height: cardH,
                    onTap: () => _onTargetTap(state, target),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _discardStack(DiscardMarker marker, int index) {
    final shown = marker.count.clamp(1, 3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 38,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var j = 0; j < shown; j++)
                Positioned(
                  left: j * 4.0,
                  top: j * 2.0,
                  child: FaceDownCard(height: 32, seed: index * 10 + j),
                ),
            ],
          ),
        ),
        Text(
          '×${marker.count}',
          style: const TextStyle(fontSize: 10, color: Tokens.textFaint),
        ),
      ],
    );
  }

  // ----------------------------------------------------------- timer

  Widget _timerStrip(GameUiState state) {
    final trick = state.trick;
    if (state.deadline <= 0 || trick == null) return const SizedBox(height: 4);
    return TurnCountdown(
      deadline: state.deadline,
      anchor: _deadlineAnchor,
      label: trick.turn == state.mySeat
          ? 'Ваш ход'
          : 'Ход: ${_nick(state, trick.turn)}',
    );
  }

  // ----------------------------------------------------------- my area

  Widget _myArea(GameUiState state) {
    SeatState? me;
    for (final s in state.seats) {
      if (s.seat == state.mySeat) me = s;
    }
    final myBubble = state.mySeat >= 0 ? _bubbles[state.mySeat] : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              const Text(
                'Вы',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Tokens.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedScoreChip(prefix: 'Очки: ', value: me?.score ?? 0),
              const SizedBox(width: 8),
              ActionChip(
                key: _anchors.wonChip,
                avatar: const Icon(
                  Icons.layers,
                  size: 16,
                  color: Tokens.gold300,
                ),
                label: PunchIn(
                  key: ValueKey('my-won-pop-${_wonPop[state.mySeat] ?? 0}'),
                  child: Text('Взятки: ${state.myWonPile.length}'),
                ),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  color: Tokens.textSecondary,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => _showWonPile(state),
              ),
              const Spacer(),
              if (myBubble != null)
                Text(myBubble, style: const TextStyle(fontSize: 22)),
            ],
          ),
        ),
        KeyedSubtree(key: _anchors.hand, child: _handWidget(state)),
      ],
    );
  }

  Widget _handWidget(GameUiState state) {
    final hand = state.myHand;
    if (hand.isEmpty) return const SizedBox(height: 20);
    const cardH = 92.0;
    final cardW = cardH * cardAspect;
    final step = cardW * 0.62;
    final legal = state.legal;
    final beatActive = _beatModeActive(state);
    List<int>? candidates;
    if (beatActive && _beatTarget != null && legal != null) {
      candidates = legal.beatMatrix[_beatTarget] ?? const <int>[];
    }
    final assignedCards = _beatAssignment.values.toSet();
    return SizedBox(
      height: cardH + 16,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 24 + step * (hand.length - 1) + cardW,
          height: cardH + 16,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < hand.length; i++)
                Positioned(
                  left: 12 + i * step,
                  top: 12,
                  child: Builder(
                    builder: (context) {
                      final dimmed =
                          assignedCards.contains(hand[i]) ||
                          (candidates != null && !candidates.contains(hand[i]));
                      final selected = _selected.contains(hand[i]);
                      return IdleLift(
                        // Gentle affordance: playable cards breathe on my turn.
                        enabled: state.isMyTurn && !dimmed && !selected,
                        phase: hand.isEmpty ? 0 : i / hand.length,
                        child: CardFace(
                          card: hand[i],
                          height: cardH,
                          selected: selected,
                          dimmed: dimmed,
                          onTap: () => _onHandTap(state, hand[i]),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWonPile(GameUiState state) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ваши взятки', style: Tokens.titleSerif),
              const SizedBox(height: 4),
              Text(
                'Очков: ${sumPoints(state.myWonPile)}',
                style: Tokens.numeric.copyWith(
                  color: Tokens.gold300,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              if (state.myWonPile.isEmpty)
                const Text(
                  'Пока пусто',
                  style: TextStyle(color: Tokens.textFaint),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in state.myWonPile)
                          CardFace(card: c, height: 64),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- action bar

  Widget _actionBar(GameUiState state, GameController controller) {
    final legal = state.legal;
    if (state.roomPhase != RoomPhase.playing ||
        legal == null ||
        !state.isMyTurn) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: switch (legal.kind) {
        'lead' => _leadActions(state, controller, legal),
        'respond' => _respondActions(state, controller, legal),
        'leaderDecision' => _leaderActions(state, controller, legal),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _leadActions(
    GameUiState state,
    GameController controller,
    LegalActions legal,
  ) {
    final selection = _selected.toList();
    final valid =
        isValidLeadSelection(selection) &&
        (legal.maxCount <= 0 || selection.length <= legal.maxCount);
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Выберите карты одного достоинства или одной масти',
            style: Tokens.caption,
          ),
        ),
        GoldButton(
          onPressed: valid
              ? () {
                  _sound.play(Sfx.buttonPress);
                  _fx.playMyLead(selection); // optimistic: flight starts now
                  controller.lead(selection);
                  setState(_selected.clear);
                }
              : null,
          child: Text(
            'Ходить${selection.isNotEmpty ? ' (${selection.length})' : ''}',
          ),
        ),
      ],
    );
  }

  Widget _respondActions(
    GameUiState state,
    GameController controller,
    LegalActions legal,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (legal.canBeat)
          SegmentedButton<bool>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: true, label: Text('Побить')),
              ButtonSegment(value: false, label: Text('Скинуть')),
            ],
            selected: {_beatMode},
            onSelectionChanged: (s) => setState(() {
              _beatMode = s.first;
              _selected.clear();
              _beatAssignment.clear();
              _beatTarget = _beatMode ? _firstUnassignedTarget(legal) : null;
            }),
          ),
        const SizedBox(height: 4),
        if (legal.canBeat && _beatMode)
          _beatButtons(controller, legal)
        else
          Row(
            children: [
              const Expanded(
                child: Text('Карты уйдут втёмную', style: Tokens.caption),
              ),
              GoldButton(
                onPressed: _selected.length == legal.discardCount
                    ? () {
                        _sound.play(Sfx.buttonPress);
                        _fx.playMyDiscard(
                          _selected.length,
                        ); // optimistic flight
                        controller.discard(_selected.toList());
                        setState(_selected.clear);
                      }
                    : null,
                child: Text(
                  'Скинуть (${_selected.length}/${legal.discardCount})',
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _beatButtons(GameController controller, LegalActions legal) {
    final targetCount = legal.beatMatrix.length;
    final complete = targetCount > 0 && _beatAssignment.length == targetCount;
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Сначала карту на столе, потом свою',
            style: Tokens.caption,
          ),
        ),
        OutlinedButton(
          onPressed: () => _autoAssign(legal),
          child: const Text('Авто'),
        ),
        const SizedBox(width: 8),
        GoldButton(
          onPressed: complete ? () => _sendBeat(controller) : null,
          child: Text('Побить (${_beatAssignment.length}/$targetCount)'),
        ),
      ],
    );
  }

  Widget _leaderActions(
    GameUiState state,
    GameController controller,
    LegalActions legal,
  ) {
    if (_beatMode && legal.canBeat) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _beatButtons(controller, legal),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _beatMode = false;
                _beatAssignment.clear();
                _beatTarget = null;
              }),
              child: const Text('Отмена'),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: GoldButton(
            onPressed: () {
              _sound.play(Sfx.buttonPress);
              controller.endTrick();
            },
            child: const Text('Закрыть круг'),
          ),
        ),
        if (legal.canBeat) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() {
                _beatMode = true;
                _beatTarget = _firstUnassignedTarget(legal);
              }),
              child: const Text('Побить самому'),
            ),
          ),
        ],
      ],
    );
  }

  // ----------------------------------------------------------- reactions

  Widget _reactionBar(GameUiState state, GameController controller) {
    if (state.roomPhase != RoomPhase.playing) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final id in _reactionIds)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => controller.react(id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  _reactionEmojis[id]!,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- overlays

  Widget _connectingOverlay() => const FeltBackground(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Подключение…'),
        ],
      ),
    ),
  );

  Widget _lobbyOverlay(GameUiState state, GameController controller) {
    LobbySeat? mySeat;
    for (final s in state.lobbySeats) {
      if (s.seat == state.mySeat) mySeat = s;
    }
    // Older servers don't send 'you' (mySeat stays -1) — fall back to the
    // first listed seat rather than nickname matching (nicknames collide).
    if (mySeat == null && state.mySeat < 0 && state.lobbySeats.isNotEmpty) {
      mySeat = state.lobbySeats.first;
    }
    final ready = mySeat?.ready ?? _myReadyLocal;
    return FeltBackground(
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Выйти',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _confirmLeave,
                ),
                const Text('Ждём игроков', style: Tokens.titleSerif),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final s in state.lobbySeats)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Tokens.felt600,
                          child: Text(
                            _initial(s.nickname),
                            style: const TextStyle(
                              color: Tokens.textPrimary,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                s.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (s.isHost) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.star,
                                size: 16,
                                color: Tokens.gold300,
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          s.connected ? 'В сети' : 'Не в сети',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                s.connected ? Tokens.success : Colors.grey,
                          ),
                        ),
                        trailing: Icon(
                          s.ready
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: s.ready ? Tokens.success : Tokens.textFaint,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    state.lobbyCanStart
                        ? 'Все готовы — начинаем!'
                        : 'Ждём, пока все игроки будут готовы…',
                    style: const TextStyle(color: Tokens.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: GoldButton(
                      icon: Icon(ready ? Icons.close : Icons.check),
                      onPressed: () {
                        _sound.play(Sfx.buttonPress);
                        controller.setReady(!ready);
                        setState(() => _myReadyLocal = !ready);
                      },
                      child: Text(ready ? 'Не готов' : 'Готов'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dealOverlay(GameUiState state) {
    final results = state.lastDealResults!;
    return GestureDetector(
      onTap: () => setState(() => _showDealOverlay = false),
      child: Container(
        color: Tokens.felt900.withValues(alpha: 0.7),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Container(
          decoration: BoxDecoration(
            color: Tokens.surfaceHigh,
            borderRadius: BorderRadius.circular(Tokens.r20),
            boxShadow: const [Tokens.shadowRaised],
          ),
          child: CustomPaint(
            foregroundPainter: const GoldFramePainter(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Итоги раздачи', style: Tokens.headlineSerif),
                  const SizedBox(height: 6),
                  const GoldRule(),
                  if (state.multiplier > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: PunchIn(
                        delay: const Duration(milliseconds: 350),
                        child: BrassChip(
                          text: 'Множитель ×${state.multiplier}',
                          danger: state.multiplier >= 3,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < results.length; i++)
                    SlideFadeIn(
                      delay: Duration(milliseconds: 110 * i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            // 120px keeps the points column aligned across
                            // rows; Flexible lets it shrink on ≤340dp screens
                            // instead of overflowing.
                            Flexible(
                              child: SizedBox(
                                width: 120,
                                child: Text(
                                  _nick(state, results[i].seat),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            CountUpText(
                              value: results[i].cardPoints,
                              suffix: ' очк.',
                              delay: Duration(milliseconds: 250 + 110 * i),
                              duration: const Duration(milliseconds: 550),
                              style: Tokens.numeric.copyWith(
                                color: Tokens.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            CountUpText(
                              value: results[i].penalty,
                              prefix: '+',
                              delay: Duration(milliseconds: 850 + 110 * i),
                              duration: const Duration(milliseconds: 320),
                              style: Tokens.numeric.copyWith(
                                color: results[i].penalty > 0
                                    ? Tokens.danger
                                    : Tokens.success,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 12),
                            CountUpText(
                              // The penalty rolls into the running total.
                              from: results[i].score - results[i].penalty,
                              value: results[i].score,
                              prefix: '= ',
                              delay: Duration(milliseconds: 1200 + 110 * i),
                              duration: const Duration(milliseconds: 380),
                              style: Tokens.numeric.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text('Нажмите, чтобы закрыть', style: Tokens.caption),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gameOverOverlay(GameUiState state, GameController controller) {
    final goats = state.goats ?? const <int>[];
    final goatNames = goats.map((s) => _nick(state, s)).join(', ');
    final hasWinners = state.seats.any((s) => !goats.contains(s.seat));
    return Container(
      color: Tokens.felt900.withValues(alpha: 0.92),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Winners get confetti; auto-stops after one burst.
          if (goats.isNotEmpty && hasWinners)
            const Positioned.fill(
              child: ConfettiBurst(
                palette: ConfettiParticle.casinoPalette,
              ),
            ),
          Center(
            child: SingleChildScrollView(
              child: Container(
                decoration: BoxDecoration(
                  color: Tokens.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(Tokens.r20),
                ),
                child: CustomPaint(
                  foregroundPainter: const GoldFramePainter(flourishes: true),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StompIn(
                          child: Text('🐐', style: TextStyle(fontSize: 84)),
                        ),
                        const SizedBox(height: 8),
                        SlideFadeIn(
                          delay: const Duration(milliseconds: 250),
                          child: Text(
                            goatNames.isEmpty
                                ? 'Игра окончена'
                                : goats.length == 1
                                ? '$goatNames — козёл!'
                                : 'Козлы: $goatNames!',
                            textAlign: TextAlign.center,
                            style: Tokens.headlineSerif,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Column(
                            children: [
                              for (final (i, s) in state.seats.indexed)
                                SlideFadeIn(
                                  delay: Duration(milliseconds: 350 + 90 * i),
                                  child: _finalScoreRow(state, s, goats),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_rematchVoted)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Голос учтён — ждём остальных…',
                              style: TextStyle(color: Tokens.textSecondary),
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GoldButton(
                              icon: const Icon(Icons.replay),
                              onPressed: _rematchVoted
                                  ? null
                                  : () {
                                      _sound.play(Sfx.buttonPress);
                                      controller.voteRematch(true);
                                      setState(() => _rematchVoted = true);
                                    },
                              child: const Text('Реванш'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.logout),
                              label: const Text('Выйти'),
                              onPressed: _leaveNow,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _finalScoreRow(GameUiState state, SeatState s, List<int> goats) {
    final isGoat = goats.contains(s.seat);
    final isMe = s.seat == state.mySeat;
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      decoration: isMe
          ? BoxDecoration(
              color: Tokens.gold100.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(Tokens.r4),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    s.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isMe ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
                if (isGoat) ...[
                  const SizedBox(width: 4),
                  const StompIn(
                    delay: Duration(milliseconds: 500),
                    child: Text('🐐', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${state.finalScores != null && s.seat < state.finalScores!.length ? state.finalScores![s.seat] : s.score}',
            style: Tokens.numeric.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    // The goat's row shakes in shame.
    return isGoat
        ? ShakeWidget(delay: const Duration(milliseconds: 500), child: row)
        : row;
  }

  Widget _reconnectOverlay() {
    return Container(
      color: Tokens.felt900.withValues(alpha: 0.8),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Переподключение…', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _reconnectBusy
                ? null
                : () async {
                    setState(() => _reconnectBusy = true);
                    try {
                      await ref.read(roomSessionProvider.notifier).reconnect();
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Tokens.dangerDeep,
                            content: Text('Не удалось переподключиться'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _reconnectBusy = false);
                    }
                  },
            child: const Text('Переподключиться'),
          ),
        ],
      ),
    );
  }
}

/// Self-contained turn countdown strip: label, seconds left and a progress
/// bar. Owns its own periodic ticker so only this widget rebuilds while the
/// clock runs; the ticker stops as soon as the remaining time hits zero.
class TurnCountdown extends StatefulWidget {
  const TurnCountdown({
    super.key,
    required this.deadline,
    required this.anchor,
    required this.label,
  });

  /// Turn deadline, ms since epoch.
  final int deadline;

  /// When the deadline was first observed (ms since epoch); used as the
  /// progress-bar start. Falls back to `deadline - 30 s` when invalid.
  final int anchor;

  /// "Ваш ход" / "Ход: <ник>" — computed by the parent, static per turn.
  final String label;

  @override
  State<TurnCountdown> createState() => _TurnCountdownState();
}

class _TurnCountdownState extends State<TurnCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(TurnCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) _syncTicker();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _remaining =>
      max(0, widget.deadline - DateTime.now().millisecondsSinceEpoch);

  void _syncTicker() {
    _timer?.cancel();
    _timer = null;
    if (_remaining <= 0) return;
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
      if (_remaining <= 0) {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final anchor = widget.anchor > 0 && widget.anchor < widget.deadline
        ? widget.anchor
        : widget.deadline - 30000;
    final total = max(1, widget.deadline - anchor);
    final value = (remaining / total).clamp(0.0, 1.0);
    final urgent = remaining < 5000;
    return Container(
      decoration: BoxDecoration(
        // Faint brass rail line above the timer strip.
        border: Border(
          top: BorderSide(
            color: Tokens.gold600.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Tokens.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${(remaining / 1000).ceil()} с',
                style: Tokens.numeric.copyWith(
                  fontSize: 12,
                  color: urgent ? Tokens.danger : Tokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: Tokens.felt900.withValues(alpha: 0.6),
              color: urgent ? Tokens.danger : Tokens.gold300,
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final e in this) {
      return e;
    }
    return null;
  }
}
