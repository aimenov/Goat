/// Room list: browse open tables, quick-join, or create a new one.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cosmetics.dart';
import '../../core/net/api.dart';
import '../../core/profile.dart';
import '../../core/render_mode.dart';
import '../../core/services/ads/ads_service.dart';
import '../../core/services/sound.dart';
import '../../core/session.dart';
import '../../shared/cards/suit_paths.dart';
import '../../shared/felt/felt_background.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/hover_lift.dart';
import '../economy/daily_bonus_sheet.dart';
import '../economy/quests_sheet.dart';
import '../game/anim/motion_widgets.dart';
import 'profile_header.dart';

/// Whether the CPU-render-mode hint was already shown this app session —
/// module-level so revisiting the lobby doesn't repeat it.
bool _cpuHintShown = false;

/// Whether the daily-bonus sheet already auto-opened this app session —
/// module-level so returning from a game doesn't nag again.
bool _dailySheetAutoOpened = false;

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  List<RoomListing>? _rooms;
  String? _error;
  bool _busy = false;
  Timer? _refreshTimer;

  // Hoisted out of _openCreateSheet: disposing a local controller right after
  // the sheet's future resolves lands mid exit-animation, while the sheet's
  // TextField still uses it ("used after being disposed" → red error flash).
  final TextEditingController _createNameController = TextEditingController();

  // Stagger-in guard: only rooms that weren't in the previous snapshot
  // animate, so the 5 s silent refresh never replays the entrance.
  final Set<String> _seenRooms = {};
  Set<String> _newRooms = const {};

  ProviderSubscription<AsyncValue<PlayerProfile>>? _profileSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh(silent: true));
    // Economy profile: refreshed by _refresh() above; auto-open the daily
    // sheet once per session as soon as a load reports a claimable bonus.
    _profileSub = ref.listenManual(
      profileProvider,
      (_, next) => _maybeAutoOpenDaily(next.value),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAutoOpenDaily(ref.read(profileProvider).value);
    });
    // Ads init from the lobby only (idempotent inside the service): the UMP
    // consent form, when required, may appear here — never over login or the
    // game table. Fire-and-forget; the service swallows its own failures.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(adsServiceProvider).init();
    });
    if (cpuRenderMode && !_cpuHintShown) {
      _cpuHintShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 8),
            content: Text(
              'Игра работает в режиме совместимости — графика упрощена и '
              'может подтормаживать. Закройте вкладку и откройте игру '
              'заново, чтобы вернуть аппаратное ускорение.',
            ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _profileSub?.close();
    _createNameController.dispose();
    super.dispose();
  }

  /// Session-once: pops the daily sheet the first time a profile load says
  /// today's bonus is claimable.
  void _maybeAutoOpenDaily(PlayerProfile? profile) {
    if (_dailySheetAutoOpened || profile == null || !profile.dailyClaimable) {
      return;
    }
    _dailySheetAutoOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showDailyBonusSheet(context);
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) unawaited(ref.read(profileProvider.notifier).refresh());
    try {
      final rooms = await ref.read(apiProvider).listRooms();
      if (!mounted) return;
      setState(() {
        _newRooms = {
          for (final r in rooms)
            if (!_seenRooms.contains(r.roomId)) r.roomId,
        };
        _seenRooms.addAll(rooms.map((r) => r.roomId));
        _rooms = rooms;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      if (!silent || _rooms == null) {
        setState(() => _error = 'Не удалось загрузить список столов');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Tokens.dangerDeep, content: Text(message)),
    );
  }

  Future<void> _guarded(Future<void> Function() action, String errorMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) context.go('/table');
    } catch (_) {
      if (mounted) _showError(errorMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(RoomListing room) => _guarded(
        () => ref.read(roomSessionProvider.notifier).joinRoom(room.roomId),
        'Не удалось сесть за стол «${room.name}»',
      );

  Future<void> _quickJoin() => _guarded(
        () => ref.read(roomSessionProvider.notifier).quickJoin(),
        'Не удалось найти игру',
      );

  Future<void> _openCreateSheet() async {
    var players = 4;
    var scoreLimit = 24;
    var turnSeconds = 30;
    _createNameController.clear();

    final create = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.r20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Новый стол', style: Tokens.titleSerif),
                const SizedBox(height: 16),
                const Text('Игроки'),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 2, label: Text('2')),
                    ButtonSegment(value: 3, label: Text('3')),
                    ButtonSegment(value: 4, label: Text('4')),
                    ButtonSegment(value: 6, label: Text('6')),
                  ],
                  selected: {players},
                  onSelectionChanged: (s) => setSheetState(() => players = s.first),
                ),
                const SizedBox(height: 12),
                const Text('Лимит очков'),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 24, label: Text('24')),
                    ButtonSegment(value: 36, label: Text('36')),
                  ],
                  selected: {scoreLimit},
                  onSelectionChanged: (s) => setSheetState(() => scoreLimit = s.first),
                ),
                const SizedBox(height: 12),
                const Text('Секунд на ход'),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 15, label: Text('15')),
                    ButtonSegment(value: 30, label: Text('30')),
                    ButtonSegment(value: 45, label: Text('45')),
                  ],
                  selected: {turnSeconds},
                  onSelectionChanged: (s) => setSheetState(() => turnSeconds = s.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _createNameController,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'Название стола (необязательно)',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                GoldButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Создать'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final name = _createNameController.text.trim();
    if (create != true) return;
    // One transition beat: let the sheet's pop animation finish before the
    // page stack swaps — go('/table') while the pageless route is still
    // mid-pop trips Navigator assertions (whole-screen red flash).
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    await _guarded(
      () => ref.read(roomSessionProvider.notifier).createRoom(
            playerCount: players,
            scoreLimit: scoreLimit,
            turnSeconds: turnSeconds,
            name: name.isEmpty ? null : name,
          ),
      'Не удалось создать стол',
    );
  }

  Widget _roomTile(RoomListing room, int staggerIndex) {
    final full = room.clients >= room.playerCount;
    final joinable = !room.started && !full;
    final Widget tile = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _BrassChipStack(
          label: '${room.clients}/${room.playerCount}',
          started: room.started,
        ),
        title: Text(
          room.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: Tokens.sansFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Tokens.textPrimary,
          ),
        ),
        subtitle: Text(
          'Игроки: ${room.clients}/${room.playerCount} · До ${room.scoreLimit} очков · ${room.turnSeconds} с/ход'
          '${room.started ? ' · Идёт игра' : ''}',
          style: const TextStyle(fontSize: 12, color: Tokens.textSecondary),
        ),
        trailing: FilledButton.tonal(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? Tokens.felt900.withValues(alpha: 0.4)
                  : Tokens.gold400.withValues(alpha: 0.16),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? Tokens.textFaint
                  : Tokens.gold200,
            ),
            minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
          ),
          onPressed: joinable && !_busy ? () => _join(room) : null,
          child: Text(room.started ? 'Играют' : (full ? 'Мест нет' : 'Сесть')),
        ),
      ),
    );
    final lifted = HoverLift(child: tile);
    if (!_newRooms.contains(room.roomId)) return lifted;
    return SlideFadeIn(
      delay: Duration(milliseconds: 40 * staggerIndex),
      offset: 18,
      child: lifted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    Widget body;
    if (rooms == null && _error == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: () => _refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 160),
          children: [
            // Economy header: its own Consumer so profile updates rebuild
            // the plaque alone; hidden while signed out.
            Consumer(
              builder: (context, ref, _) {
                final identity = ref.watch(identityProvider).value;
                if (identity == null) return const SizedBox.shrink();
                final profile =
                    ref.watch(profileProvider).value ?? const PlayerProfile();
                return ProfileHeader(
                  nickname: identity.nickname,
                  profile: profile,
                  onCoins: () => context.push('/shop'),
                  onRating: () => context.push('/leaderboard'),
                  onQuests: () => showQuestsSheet(context),
                );
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Tokens.danger),
                ),
              ),
            if (rooms != null && rooms.isEmpty && _error == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Открытых столов нет.\nСоздайте свой или нажмите «Быстрая игра»!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Tokens.textSecondary),
                ),
              ),
            if (rooms != null)
              for (var i = 0; i < rooms.length; i++) _roomTile(rooms[i], i),
          ],
        ),
      );
    }

    return FeltBackground(
      theme: ref.watch(cosmeticsProvider).felt,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Столы'),
          actions: [
            IconButton(
              tooltip: 'Звук',
              icon: Icon(
                ref.read(soundServiceProvider).muted
                    ? Icons.volume_off
                    : Icons.volume_up,
              ),
              onPressed: () =>
                  setState(ref.read(soundServiceProvider).toggleMuted),
            ),
            IconButton(
              tooltip: 'Достижения',
              icon: const Icon(Icons.emoji_events),
              onPressed: () => context.push('/achievements'),
            ),
            IconButton(
              tooltip: 'Сменить ник',
              icon: const Icon(Icons.person_outline),
              onPressed: () => context.go('/login'),
            ),
            IconButton(
              tooltip: 'Обновить',
              icon: const Icon(Icons.refresh),
              onPressed: () => _refresh(),
            ),
          ],
        ),
        body: body,
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'quickJoin',
              onPressed: _busy ? null : _quickJoin,
              backgroundColor: Tokens.gold400,
              foregroundColor: Tokens.onGold,
              icon: const Icon(Icons.flash_on),
              label: const Text('Быстрая игра'),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'createRoom',
              onPressed: _busy ? null : _openCreateSheet,
              backgroundColor: Tokens.surfaceHigh,
              foregroundColor: Tokens.gold200,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tokens.r14),
                side: BorderSide(
                  color: Tokens.gold600.withValues(alpha: 0.6),
                  width: 0.8,
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Создать стол'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Room-tile leading: a 36 px brass chip — gold ring, felt disc, occupancy
/// count (or a ♠ once the game has started).
class _BrassChipStack extends StatelessWidget {
  const _BrassChipStack({required this.label, required this.started});

  final String label;
  final bool started;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _BrassChipPainter()),
          ),
          if (started)
            const SuitIcon(suit: 0, size: 14, color: Tokens.gold100)
          else
            Text(
              label,
              style: Tokens.numeric.copyWith(
                fontSize: 11,
                color: Tokens.gold100,
              ),
            ),
        ],
      ),
    );
  }
}

class _BrassChipPainter extends CustomPainter {
  const _BrassChipPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // Brass ring: radial gold500 -> gold600.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Tokens.gold500, Tokens.gold600],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    // Felt inner disc.
    canvas.drawCircle(center, r - 3.5, Paint()..color = Tokens.felt700);
    // Hairline between ring and disc.
    canvas.drawCircle(
      center,
      r - 3.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Tokens.gold300.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _BrassChipPainter oldDelegate) => false;
}
