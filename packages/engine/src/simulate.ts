/**
 * Fuzz simulator: plays whole games with random legal actions, asserting the
 * engine's invariants on every step. Used by tests and as a CLI:
 *
 *   npm run simulate -- --deals 10000
 */
import { type GameAction, TOTAL_POINTS } from '@goat/shared';
import { legalActions } from './legal.js';
import { findPerfectMatching } from './rules.js';
import { initGame, reduce } from './reduce.js';
import { splitmix32 } from './rng.js';
import type { EngineEvent, GameState } from './types.js';

const MAX_DEALS_PER_GAME = 2000;

export interface GameStats {
  deals: number;
  tricks: number;
  actions: number;
  goats: number[];
  scores: number[];
  finalState: GameState;
  actionLog: GameAction[];
}

/** Pick a uniformly random legal action for the seat to move. */
export function randomAction(state: GameState, rnd: () => number): GameAction {
  const trick = state.trick!;
  const seat = trick.turn;
  const legal = legalActions(state, seat)!;
  const hand = state.players[seat]!.hand;

  switch (legal.kind) {
    case 'lead': {
      const candidates: number[][] = hand.map((c) => [c]); // all singletons
      for (const group of Object.values(legal.rankGroups)) {
        if (group.length > 1) candidates.push(group);
      }
      for (const group of Object.values(legal.suitGroups)) {
        if (group.length > 1) {
          // a few random same-suit subsets of size ≥ 2
          const size = 2 + (rnd() % (group.length - 1));
          const pool = [...group];
          const subset: number[] = [];
          for (let i = 0; i < size; i++) subset.push(pool.splice(rnd() % pool.length, 1)[0]!);
          candidates.push(subset);
        }
      }
      return { type: 'LEAD', seat, cards: candidates[rnd() % candidates.length]! };
    }
    case 'respond': {
      const pairs = legal.canBeat ? findPerfectMatching(legal.beatMatrix) : null;
      if (pairs && rnd() % 2 === 0) return { type: 'BEAT', seat, pairs };
      const pool = [...hand];
      const cards: number[] = [];
      for (let i = 0; i < legal.discardCount; i++) cards.push(pool.splice(rnd() % pool.length, 1)[0]!);
      return { type: 'DISCARD', seat, cards };
    }
    case 'leaderDecision': {
      const pairs = legal.canBeat ? findPerfectMatching(legal.beatMatrix) : null;
      if (pairs && rnd() % 3 === 0) return { type: 'BEAT', seat, pairs };
      return { type: 'END_TRICK', seat };
    }
  }
}

export function playRandomGame(seed: number, playerCount: number, scoreLimit: number): GameStats {
  const rnd = splitmix32(seed ^ 0x5eed);
  let { state, events } = initGame({ playerCount, scoreLimit, seed });
  const actionLog: GameAction[] = [];
  let deals = 0;
  let tricks = 0;
  let actions = 0;

  const digest = (evts: EngineEvent[]) => {
    for (const e of evts) {
      if (e.type === 'trickEnded') tricks++;
      if (e.type === 'dealStarted') deals++;
      if (e.type === 'dealEnded') {
        const totalPts = e.results.reduce((s, r) => s + r.cardPoints, 0);
        if (totalPts !== TOTAL_POINTS) throw new Error(`deal points ${totalPts} != ${TOTAL_POINTS}`);
      }
    }
  };
  digest(events);

  while (state.phase !== 'GAME_OVER') {
    if (deals > MAX_DEALS_PER_GAME) throw new Error('game did not terminate');
    const action = randomAction(state, rnd);
    const result = reduce(state, action);
    if (!result.ok) {
      throw new Error(`legal action rejected: ${result.error} ${JSON.stringify(action)}`);
    }
    actionLog.push(action);
    actions++;
    state = result.state;
    digest(result.events);
  }

  return {
    deals,
    tricks,
    actions,
    goats: state.goats!,
    scores: state.players.map((p) => p.score),
    finalState: state,
    actionLog,
  };
}

/** Replay an action log from the same seed; must reproduce identical state. */
export function replay(seed: number, playerCount: number, scoreLimit: number, log: GameAction[]): GameState {
  let { state } = initGame({ playerCount, scoreLimit, seed });
  for (const action of log) {
    const result = reduce(state, action);
    if (!result.ok) throw new Error(`replay diverged: ${result.error}`);
    state = result.state;
  }
  return state;
}

const isMain = process.argv[1]?.replace(/\\/g, '/').endsWith('simulate.ts');
if (isMain) {
  const dealsTarget = Number(process.argv[process.argv.indexOf('--deals') + 1] || 1000);
  const t0 = Date.now();
  let deals = 0;
  let games = 0;
  let failures = 0;
  const perCount: Record<number, number> = { 2: 0, 3: 0, 4: 0, 6: 0 };
  while (deals < dealsTarget) {
    const playerCount = [2, 3, 4, 6][games % 4]!;
    const scoreLimit = games % 2 === 0 ? 24 : 36;
    try {
      const stats = playRandomGame(games + 1, playerCount, scoreLimit);
      // determinism: replaying the log must give identical final state
      const replayed = replay(games + 1, playerCount, scoreLimit, stats.actionLog);
      if (JSON.stringify(replayed) !== JSON.stringify(stats.finalState)) {
        throw new Error('replay mismatch');
      }
      deals += stats.deals;
      perCount[playerCount] = (perCount[playerCount] ?? 0) + stats.deals;
    } catch (err) {
      failures++;
      console.error(`game ${games + 1} (${playerCount}p): ${(err as Error).message}`);
      if (failures > 5) process.exit(1);
    }
    games++;
  }
  const secs = ((Date.now() - t0) / 1000).toFixed(1);
  console.log(
    `OK: ${games} games, ${deals} deals in ${secs}s (2p:${perCount[2]} 3p:${perCount[3]} 4p:${perCount[4]} 6p:${perCount[6]}), failures: ${failures}`,
  );
  process.exit(failures ? 1 : 0);
}
