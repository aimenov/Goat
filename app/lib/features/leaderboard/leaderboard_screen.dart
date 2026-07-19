/// «Доска почёта» (route /leaderboard): weekly капуста race and the all-time
/// rating top-50. [LeaderboardScreen] is the connected shell (fetch/refetch);
/// [LeaderboardBody] is a pure widget — testable without network.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cosmetics.dart';
import '../../core/net/api.dart';
import '../../core/session.dart';
import '../../shared/felt/felt_background.dart';
import '../../shared/theme/tokens.dart';
import '../economy/ranks.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String _scope = 'weekly';
  LeaderboardData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scope = _scope;
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final identity = await ref.read(identityProvider.future);
      final data = await ref
          .read(apiProvider)
          .leaderboard(scope, token: identity?.token);
      // A slow response for the previous scope must not clobber the new one.
      if (mounted && _scope == scope) setState(() => _data = data);
    } catch (_) {
      if (mounted && _scope == scope) {
        setState(() => _error = 'Не удалось загрузить доску почёта');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final Widget body;
    if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Tokens.danger)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
              onPressed: _load,
            ),
          ],
        ),
      );
    } else if (data == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = LeaderboardBody(
        data: data,
        scope: _scope,
        myPlayerId: ref.watch(identityProvider).value?.playerId,
      );
    }
    return FeltBackground(
      theme: ref.watch(cosmeticsProvider).felt,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Доска почёта')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<String>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: 'weekly', label: Text('Неделя')),
                  ButtonSegment(value: 'alltime', label: Text('За всё время')),
                ],
                selected: {_scope},
                onSelectionChanged: (s) {
                  _scope = s.first;
                  _load(); // _load setState()s immediately (spinner)
                },
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// The rows + the own-position footer. Pure: everything comes from [data].
class LeaderboardBody extends StatelessWidget {
  const LeaderboardBody({
    super.key,
    required this.data,
    required this.scope,
    this.myPlayerId,
  });

  final LeaderboardData data;

  /// 'weekly' | 'alltime' — picks the trailing stat.
  final String scope;
  final String? myPlayerId;

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    if (data.entries.isEmpty) {
      return const Center(
        child: Text(
          'Таблица пока пуста',
          style: TextStyle(color: Tokens.textSecondary),
        ),
      );
    }
    final me = data.me;
    final listedMine = myPlayerId != null &&
        data.entries.any((e) => e.playerId == myPlayerId);
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: data.entries.length,
            itemBuilder: (context, i) {
              final entry = data.entries[i];
              return _row(
                entry: entry,
                position: entry.position > 0 ? entry.position : i + 1,
                mine: myPlayerId != null && entry.playerId == myPlayerId,
              );
            },
          ),
        ),
        // Off-list footer: the caller's own standing under the top-50.
        if (me != null && !listedMine)
          Container(
            key: const ValueKey('lb-me-footer'),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: Tokens.surfaceHigh,
              border: Border(
                top: BorderSide(
                  color: Tokens.gold600.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    me.position > 0
                        ? 'Вы — ${me.position}-е место'
                        : 'Вы: ${me.nickname}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Tokens.gold200,
                    ),
                  ),
                ),
                Text(
                  _trailing(me),
                  style: Tokens.numeric.copyWith(color: Tokens.gold100),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _trailing(LeaderboardEntry entry) => scope == 'weekly'
      ? '🥬 ${entry.weeklyCoins}'
      : '${rankForRating(entry.rating).emoji} ${entry.rating}';

  Widget _row({
    required LeaderboardEntry entry,
    required int position,
    required bool mine,
  }) {
    return Container(
      key: mine ? const ValueKey('lb-own-row') : null,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        // Own row: felt-gold highlight (matches the game-over score rows).
        color: mine
            ? Tokens.gold100.withValues(alpha: 0.08)
            : Tokens.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Tokens.r10),
        border: mine
            ? Border.all(color: Tokens.gold400.withValues(alpha: 0.7))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              position <= _medals.length
                  ? _medals[position - 1]
                  : '$position.',
              style: position <= _medals.length
                  ? const TextStyle(fontSize: 16)
                  : Tokens.numeric.copyWith(
                      fontSize: 13,
                      color: Tokens.textFaint,
                    ),
            ),
          ),
          Expanded(
            child: Text(
              entry.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: mine ? FontWeight.w800 : FontWeight.w500,
                color: Tokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _trailing(entry),
            style: Tokens.numeric.copyWith(
              fontSize: 13,
              color: mine ? Tokens.gold100 : Tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
