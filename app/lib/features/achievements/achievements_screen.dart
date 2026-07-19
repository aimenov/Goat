/// Achievements & lifetime stats screen (route /achievements) — the trophy
/// wall: brass stats plaque, gold-framed unlocked tiles with a soft halo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cosmetics.dart';
import '../../core/net/api.dart';
import '../../core/session.dart';
import '../../shared/felt/felt_background.dart';
import '../../shared/fx/radial_glow.dart';
import '../../shared/theme/tokens.dart';
import '../game/anim/motion_widgets.dart';
import 'achievements.dart';

class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen> {
  PlayerProfile? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _profile = null;
      _error = null;
    });
    try {
      final identity = await ref.read(identityProvider.future);
      // No identity yet — nothing earned; show the full locked gallery.
      final profile = identity == null
          ? const PlayerProfile()
          : await ref.read(apiProvider).profile(identity.playerId);
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось загрузить достижения');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
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
    } else if (profile == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: AchievementsBody(profile: profile),
      );
    }
    return FeltBackground(
      theme: ref.watch(cosmeticsProvider).felt,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Достижения')),
        body: body,
      ),
    );
  }
}

/// Stats header + the full 12-achievement grid. Pure widget — testable
/// without network or providers.
class AchievementsBody extends StatelessWidget {
  const AchievementsBody({super.key, required this.profile});

  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    final unlockedCount =
        achievementDefs.where((d) => profile.unlocked.contains(d.id)).length;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _statsHeader(),
        const SizedBox(height: 16),
        Text(
          'Открыто $unlockedCount из ${achievementDefs.length}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Tokens.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: [
            for (final (i, def) in achievementDefs.indexed)
              SlideFadeIn(
                delay: Duration(milliseconds: 30 * i),
                child: _AchievementTile(
                  def: def,
                  unlocked: profile.unlocked.contains(def.id),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Brass plaque: raised surface, double gold hairline, numeric values.
  Widget _statsHeader() {
    final s = profile.stats;
    return Container(
      decoration: BoxDecoration(
        color: Tokens.surfaceHigh,
        borderRadius: BorderRadius.circular(Tokens.r14),
        border: Border.all(
          color: Tokens.gold400.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Tokens.r14 - 2),
          border: Border.all(
            color: Tokens.gold600.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            _statCell('🎲', s.gamesPlayed, 'Сыграно'),
            _statCell('🏆', s.gamesWon, 'Побед'),
            _statCell('🐐', s.goats, 'Раз козлом'),
            _statCell('🔥', s.winStreak, 'Серия побед'),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String emoji, int value, String label) => Expanded(
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              '$value',
              style: Tokens.numeric.copyWith(
                fontSize: 20,
                color: Tokens.gold100,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, color: Tokens.textFaint),
              ),
            ),
          ],
        ),
      );
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.def, required this.unlocked});

  final AchievementDef def;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked
            ? Tokens.surfaceHigh
            : Tokens.felt900.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(Tokens.r14),
        border: Border.all(
          color: unlocked
              ? Tokens.gold400
              : Tokens.gold600.withValues(alpha: 0.2),
          width: unlocked ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (unlocked)
            Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CustomPaint(
                    painter: RadialGlowPainter(
                      color: Tokens.gold300,
                      opacity: 0.22,
                    ),
                  ),
                ),
                Text(def.emoji, style: const TextStyle(fontSize: 34)),
              ],
            )
          else
            Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 0.25,
                  child: Text(def.emoji, style: const TextStyle(fontSize: 34)),
                ),
                const Icon(Icons.lock, size: 20, color: Tokens.textFaint),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            def.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: unlocked ? Tokens.gold200 : Tokens.textFaint,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            def.description,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: unlocked ? Tokens.textSecondary : Tokens.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}
