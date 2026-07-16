/// GlobalKey registry for the table regions the flight overlay targets:
/// stock/trump indicator, trick area, my hand, my won-pile chip, the discard
/// clump and each opponent seat tile. Resolution is best-effort — a missing
/// or unlaid-out anchor yields null and the caller falls back or skips.
library;

import 'package:flutter/widgets.dart';

class TableAnchors {
  final stock = GlobalKey(debugLabel: 'anchor-stock');
  final trick = GlobalKey(debugLabel: 'anchor-trick');
  final hand = GlobalKey(debugLabel: 'anchor-hand');
  final wonChip = GlobalKey(debugLabel: 'anchor-wonChip');
  final discard = GlobalKey(debugLabel: 'anchor-discard');
  final Map<int, GlobalKey> _seats = {};

  /// Stable per-seat key (created on first use).
  GlobalKey seat(int seat) => _seats.putIfAbsent(
    seat,
    () => GlobalKey(debugLabel: 'anchor-seat-$seat'),
  );

  /// Global (screen) center of the region, or null when unavailable.
  Offset? globalCenterOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(ro.size.center(Offset.zero));
  }
}
