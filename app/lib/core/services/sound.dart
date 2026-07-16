/// SoundService — implements docs/design/design-sound.md §3.
/// Tactile SFX play through per-sound [AudioPool]s (rapid-fire safe); chimes
/// share two stealable [AudioPlayer] slots so they never stack on themselves.
/// All calls are fire-and-forget and cooldown-checked; on web nothing plays
/// until the first user gesture ([markUnlocked]).
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Sfx {
  // cooldown below the 70 ms multi-card stagger so 3-card slides all sound
  cardSlide('card_slide', maxPlayers: 3, cooldownMs: 60),
  cardSnap('card_snap', maxPlayers: 3, cooldownMs: 60),
  cardFlip('card_flip', maxPlayers: 2, cooldownMs: 70),
  dealRiffle('deal_riffle', maxPlayers: 1, cooldownMs: 900),
  stackThud('stack_thud', maxPlayers: 1, cooldownMs: 250),
  tapSelect('tap_select', maxPlayers: 2, cooldownMs: 50),
  buttonPress('button_press', maxPlayers: 2, cooldownMs: 100),
  trumpChime('trump_chime', chime: true, cooldownMs: 1000),
  myTurnDing('my_turn_ding', chime: true, cooldownMs: 1500),
  achievementBell('achievement_bell', chime: true, cooldownMs: 1000),
  winFanfare('win_fanfare', chime: true, cooldownMs: 1000),
  goatMoan('goat_moan', chime: true, cooldownMs: 1000),
  shohaImpact('shoha_impact', chime: true, cooldownMs: 1000),
  reactionPop('reaction_pop', maxPlayers: 2, cooldownMs: 300);

  const Sfx(this.file, {this.maxPlayers = 1, this.chime = false, required this.cooldownMs});

  final String file;
  final int maxPlayers;
  final bool chime;
  final int cooldownMs;

  String get assetPath => 'sounds/$file.wav';
}

class SoundService {
  final _pools = <Sfx, AudioPool>{};
  final _chimeSlots = <AudioPlayer>[];
  final _lastPlayed = <Sfx, DateTime>{};
  final _delayed = <Timer>{};
  int _nextChimeSlot = 0;
  bool _unlocked = !kIsWeb; // web needs a user gesture first
  bool _initialized = false;

  double _volume = 0.8;
  bool _muted = false;

  double get volume => _volume;
  bool get muted => _muted;

  /// Riffle-coalescing window for replenishment draws (spec §1).
  DateTime _drawWindowEnd = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _volume = prefs.getDouble('sound.volume') ?? 0.8;
      _muted = prefs.getBool('sound.muted') ?? false;

      for (final sfx in Sfx.values.where((s) => !s.chime)) {
        try {
          _pools[sfx] = await AudioPool.createFromAsset(path: sfx.assetPath, maxPlayers: sfx.maxPlayers);
        } catch (_) {
          // one bad asset must not silence the rest
        }
      }
      for (var i = 0; i < 2; i++) {
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        _chimeSlots.add(player);
      }
    } catch (_) {
      // Sound must never break the game (e.g. missing audio backend in tests).
    }
  }

  /// First user gesture on web resumes the audio context.
  void markUnlocked() {
    _unlocked = true;
  }

  set volume(double v) {
    _volume = v.clamp(0.0, 1.0);
    SharedPreferences.getInstance().then((p) => p.setDouble('sound.volume', _volume));
  }

  set muted(bool m) {
    _muted = m;
    SharedPreferences.getInstance().then((p) => p.setBool('sound.muted', _muted));
  }

  void toggleMuted() => muted = !_muted;

  void play(Sfx sfx, {double gain = 1.0}) {
    if (_muted || !_unlocked || !_initialized) return;
    final v = (gain * _volume).clamp(0.0, 1.0);
    if (v <= 0) return;
    final now = DateTime.now();
    final last = _lastPlayed[sfx];
    if (last != null && now.difference(last).inMilliseconds < sfx.cooldownMs) return;
    _lastPlayed[sfx] = now;
    try {
      if (sfx.chime) {
        final slot = _chimeSlots.isEmpty ? null : _chimeSlots[_nextChimeSlot % _chimeSlots.length];
        _nextChimeSlot++;
        slot
          ?..stop()
          ..play(AssetSource(sfx.assetPath), volume: v);
      } else {
        _pools[sfx]?.start(volume: v);
      }
    } catch (_) {
      // fire-and-forget
    }
  }

  void playDelayed(Sfx sfx, Duration delay, {double gain = 1.0}) {
    late final Timer timer;
    timer = Timer(delay, () {
      _delayed.remove(timer);
      play(sfx, gain: gain);
    });
    _delayed.add(timer);
  }

  /// Drops all pending [playDelayed] sounds — call when leaving the table so
  /// a scheduled thud/chime can't play on the next screen.
  void cancelDelayed() {
    for (final t in _delayed) {
      t.cancel();
    }
    _delayed.clear();
  }

  /// Draw coalescing: many yourDraw/cardDrawn events → one riffle per window.
  void drawBatch() {
    final now = DateTime.now();
    if (now.isBefore(_drawWindowEnd)) {
      _drawWindowEnd = now.add(const Duration(milliseconds: 700));
      return;
    }
    _drawWindowEnd = now.add(const Duration(milliseconds: 700));
    play(Sfx.dealRiffle);
  }

  /// Resets the riffle window (called on dealStarted).
  void resetDrawWindow() {
    _drawWindowEnd = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void dispose() {
    for (final t in _delayed) {
      t.cancel();
    }
    _delayed.clear();
    for (final p in _chimeSlots) {
      p.dispose();
    }
    for (final pool in _pools.values) {
      pool.dispose();
    }
  }
}

final soundServiceProvider = Provider<SoundService>((ref) {
  final service = SoundService();
  ref.onDispose(service.dispose);
  return service;
});
