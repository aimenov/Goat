/**
 * Deterministic, serializable PRNG (xoshiro128** seeded via splitmix32).
 * State is a plain 4-tuple of uint32 so GameState stays JSON-serializable.
 */

export type RngState = [number, number, number, number];

export function splitmix32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x9e3779b9) >>> 0;
    let t = a;
    t ^= t >>> 16;
    t = Math.imul(t, 0x21f0aaad);
    t ^= t >>> 15;
    t = Math.imul(t, 0x735a2d97);
    t ^= t >>> 15;
    return t >>> 0;
  };
}

export function seedRng(seed: number): RngState {
  const sm = splitmix32(seed);
  const s: RngState = [sm(), sm(), sm(), sm()];
  // xoshiro must not start at all-zero state
  if (s[0] === 0 && s[1] === 0 && s[2] === 0 && s[3] === 0) s[0] = 1;
  return s;
}

const rotl = (x: number, k: number): number => ((x << k) | (x >>> (32 - k))) >>> 0;

/** Advance the state in place; returns a uint32. */
export function nextUint32(s: RngState): number {
  const result = (Math.imul(rotl(Math.imul(s[1], 5) >>> 0, 7), 9) >>> 0) >>> 0;
  const t = (s[1] << 9) >>> 0;
  s[2] = (s[2] ^ s[0]) >>> 0;
  s[3] = (s[3] ^ s[1]) >>> 0;
  s[1] = (s[1] ^ s[2]) >>> 0;
  s[0] = (s[0] ^ s[3]) >>> 0;
  s[2] = (s[2] ^ t) >>> 0;
  s[3] = rotl(s[3], 11);
  return result;
}

/** Uniform integer in [0, n). */
export function nextInt(s: RngState, n: number): number {
  // rejection sampling to avoid modulo bias
  const limit = Math.floor(0x100000000 / n) * n;
  let x = nextUint32(s);
  while (x >= limit) x = nextUint32(s);
  return x % n;
}

/** In-place Fisher–Yates shuffle. */
export function shuffle<T>(s: RngState, arr: T[]): T[] {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = nextInt(s, i + 1);
    const tmp = arr[i]!;
    arr[i] = arr[j]!;
    arr[j] = tmp;
  }
  return arr;
}
