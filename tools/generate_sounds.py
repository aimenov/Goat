"""Procedural SFX generator for Goat (Козёл) — implements docs/design/design-sound.md §2.

Deterministic (fixed seed); writes 22,050 Hz 16-bit mono WAVs to app/assets/sounds/.
Run:  py tools/generate_sounds.py
"""

from __future__ import annotations

import os
import wave

import numpy as np

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "app", "assets", "sounds")
rng = np.random.default_rng(0xC0A7)


# ---------------------------------------------------------------- primitives

def noise(n: int) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, n)


def _fft_mask(n: int, gain_of_f) -> np.ndarray:
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    return gain_of_f(freqs)


def _skirt(f: np.ndarray, edge: float, side: str) -> np.ndarray:
    """Gaussian skirt in log2-frequency, sigma = 1/3 octave, outside the edge."""
    with np.errstate(divide="ignore"):
        octaves = np.log2(np.maximum(f, 1e-9) / edge)
    gain = np.exp(-0.5 * (octaves / (1.0 / 3.0)) ** 2)
    if side == "below":  # unit gain above the edge
        return np.where(f >= edge, 1.0, gain)
    return np.where(f <= edge, 1.0, gain)


def bp(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    spec *= _skirt(f, lo, "below") * _skirt(f, hi, "above")
    return np.fft.irfft(spec, len(x))


def lp(x: np.ndarray, fc: float) -> np.ndarray:
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    spec *= _skirt(f, fc, "above")
    return np.fft.irfft(spec, len(x))


def hp(x: np.ndarray, fc: float) -> np.ndarray:
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    spec *= _skirt(f, fc, "below")
    return np.fft.irfft(spec, len(x))


def samples(ms: float) -> int:
    return int(SR * ms / 1000.0)


def t_axis(n: int) -> np.ndarray:
    return np.arange(n) / SR


def expdec(n: int, tau_ms: float, start_ms: float = 0.0) -> np.ndarray:
    t = t_axis(n) - start_ms / 1000.0
    env = np.exp(-np.maximum(t, 0.0) / (tau_ms / 1000.0))
    env[t < 0] = 0.0
    return env


def glide_sine(f_of_t: np.ndarray) -> np.ndarray:
    return np.sin(2.0 * np.pi * np.cumsum(f_of_t) / SR)


def const_freq(freq: float, n: int) -> np.ndarray:
    return np.full(n, float(freq))


def attack(env: np.ndarray, a_ms: float) -> np.ndarray:
    a = samples(a_ms)
    if a > 0:
        ramp = np.linspace(0.0, 1.0, a)
        env = env.copy()
        env[:a] *= ramp
    return env


def fade_out(x: np.ndarray, ms: float) -> np.ndarray:
    f = samples(ms)
    if f > 0:
        x = x.copy()
        x[-f:] *= np.linspace(1.0, 0.0, f)
    return x


def detuned_pair(freq: float, n: int, detune: float, tau_ms: float, a_ms: float = 4.0) -> np.ndarray:
    env = attack(expdec(n, tau_ms), a_ms)
    return 0.5 * (glide_sine(const_freq(freq * (1 + detune), n)) + glide_sine(const_freq(freq * (1 - detune), n))) * env


def place(dest: np.ndarray, grain: np.ndarray, at_ms: float, gain: float = 1.0) -> None:
    i = samples(at_ms)
    j = min(len(dest), i + len(grain))
    if i < len(dest):
        dest[i:j] += grain[: j - i] * gain


def write_wav(name: str, x: np.ndarray, mix: float) -> int:
    # peak-normalize, apply baked mix gain
    x = x / max(np.max(np.abs(x)), 1e-9) * mix
    # FFT lowpass at 9.5 kHz then decimate 2x -> 22050 Hz
    x = lp(x, 9500.0)[::2]
    # triangular dither +-0.5 LSB
    lsb = 1.0 / 32768.0
    x = x + (rng.uniform(-0.5, 0.5, len(x)) + rng.uniform(-0.5, 0.5, len(x))) * lsb
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    path = os.path.join(OUT_DIR, f"{name}.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR // 2)
        w.writeframes(pcm.tobytes())
    return os.path.getsize(path)


# ------------------------------------------------------------------ tactile

def card_slide() -> np.ndarray:
    n = samples(140)
    t = t_axis(n)
    a = bp(noise(n), 1200, 4500)
    peak = 0.055
    env_a = np.where(t <= peak, np.sin(np.pi / 2 * t / peak) ** 2, np.clip(1 - (t - peak) / (0.14 - peak), 0, 1))
    b = bp(noise(n), 4000, 8000) * (t / 0.14) ** 2 * expdec(n, 45, start_ms=60)
    return a * env_a + 0.5 * b


def card_snap() -> np.ndarray:
    n = samples(60)
    crack = bp(noise(n), 2000, 8000) * attack(expdec(n, 18), 1)
    body = glide_sine(const_freq(180, n)) * expdec(n, 25)
    return fade_out(crack + 0.35 * body, 5)


def card_flip() -> np.ndarray:
    n = samples(90)
    out = np.zeros(n)
    g = samples(40)
    place(out, bp(noise(g), 1500, 6000) * expdec(g, 10), 0, 0.5)
    place(out, bp(noise(g), 1500, 6000) * expdec(g, 20), 45, 1.0)
    place(out, glide_sine(const_freq(300, g)) * expdec(g, 15), 45, 0.25)
    return out


def deal_riffle() -> np.ndarray:
    n = samples(380)
    out = np.zeros(n)
    onsets = [0, 45, 95, 150, 210, 275, 330]
    for k, base in enumerate(onsets):
        g = samples(60)
        c = 3000 * 2 ** rng.uniform(-0.3, 0.3)
        grain = bp(noise(g), c / 1.8, c * 1.8) * np.hanning(g)
        gain = (0.7 if k % 2 == 0 else 1.0) * (1 + rng.uniform(-0.1, 0.1))
        place(out, grain, base + rng.uniform(-8, 8), gain)
    return out


def stack_thud() -> np.ndarray:
    n = samples(180)
    t = t_axis(n)
    f = np.where(t < 0.08, 110 * (70 / 110) ** (t / 0.08), 70.0)
    a = glide_sine(f) * attack(expdec(n, 60), 2)
    b = lp(noise(n), 600) * expdec(n, 30)
    c = bp(noise(n), 400, 1200) * expdec(n, 15)
    return a + 0.4 * b + 0.25 * c


def tap_select() -> np.ndarray:
    n = samples(35)
    return glide_sine(const_freq(1100, n)) * expdec(n, 8) + 0.3 * bp(noise(n), 3000, 7000) * expdec(n, 4)


def button_press() -> np.ndarray:
    n = samples(45)
    t = t_axis(n)
    tone = (np.sin(2 * np.pi * 700 * t) + 0.3 * np.sin(2 * np.pi * 2100 * t)) * expdec(n, 12)
    return tone + 0.25 * bp(noise(n), 2000, 5000) * expdec(n, 5)


# ------------------------------------------------------------------- chimes

def _bell_note(n: int, f0: float, ratios, gains, taus, a_ms=4.0, detune=0.003) -> np.ndarray:
    out = np.zeros(n)
    for r, g, tau in zip(ratios, gains, taus):
        out += g * detuned_pair(f0 * r, n, detune, tau, a_ms)
    return out


def trump_chime() -> np.ndarray:
    n = samples(700)
    out = np.zeros(n)
    note = samples(560)
    ratios, gains, taus = [1.0, 2.76, 5.40], [1.0, 0.35, 0.12], [280, 140, 80]
    place(out, _bell_note(note, 659.25, ratios, gains, taus), 0, 1.0)
    place(out, _bell_note(note, 987.77, ratios, gains, taus), 120, 0.9)
    return out


def my_turn_ding() -> np.ndarray:
    n = samples(450)
    fund = detuned_pair(880, n, 0.004, 180, a_ms=5)
    octave = glide_sine(const_freq(1760, n)) * attack(expdec(n, 90), 5)
    return fund + 0.3 * octave


def achievement_bell() -> np.ndarray:
    n = samples(900)
    f0 = 1046.5
    ratios = [0.56, 0.92, 1.0, 1.19, 1.70, 2.00]
    gains = [0.4, 0.6, 1.0, 0.5, 0.35, 0.25]
    taus = [500, 400, 350, 250, 180, 120]
    out = np.zeros(n)
    for r, g, tau in zip(ratios, gains, taus):
        if r >= 1.0:
            out += g * detuned_pair(f0 * r, n, 0.002, tau, 3)
        else:
            out += g * glide_sine(const_freq(f0 * r, n)) * attack(expdec(n, tau), 3)
    out += 0.2 * bp(noise(n), 3000, 8000) * expdec(n, 8)
    return out


def win_fanfare() -> np.ndarray:
    n = samples(1500)
    out = np.zeros(n)

    def tri_note(f: float, length_ms: float, tau: float) -> np.ndarray:
        m = samples(length_ms)
        t = t_axis(m)
        tone = sum((1.0 / (h * h)) * np.sin(2 * np.pi * f * h * t) for h in (1, 3, 5))
        return tone * attack(expdec(m, tau), 8)

    place(out, tri_note(523.25, 500, 260), 0)
    place(out, tri_note(659.25, 500, 260), 220)
    note3 = tri_note(783.99, 1060, 600)
    m = len(note3)
    note3 += 0.35 * np.sin(2 * np.pi * 1568.0 * t_axis(m)) * attack(expdec(m, 600), 8)
    place(out, note3, 440)
    for _ in range(8):
        g = samples(200)
        grain = glide_sine(const_freq(rng.uniform(2000, 5000), g)) * expdec(g, 60)
        place(out, grain, rng.uniform(500, 1200), 0.15)
    return fade_out(out, 300)


def goat_moan() -> np.ndarray:
    n = samples(850)
    t = t_axis(n)
    f = np.empty(n)
    seg1 = t < 0.25
    f[seg1] = 220 * (180 / 220) ** (t[seg1] / 0.25)
    seg2 = (t >= 0.25) & (t < 0.30)
    f[seg2] = 180
    seg3 = (t >= 0.30) & (t < 0.70)
    f[seg3] = 180 * (130 / 180) ** ((t[seg3] - 0.30) / 0.40)
    f[t >= 0.70] = 130
    f = f * (1 + 0.03 * np.sin(2 * np.pi * 5.5 * t))
    tone = sum(g * glide_sine(f * h) for h, g in zip((1, 2, 3, 4), (1.0, 0.5, 0.33, 0.25)))
    env = attack(np.ones(n), 60) * (1 + 0.25 * np.sin(2 * np.pi * 6 * t)) / 1.25
    rel = samples(200)
    env[-rel:] *= np.linspace(1.0, 0.0, rel)
    return lp(tone * env, 2200)


def shoha_impact() -> np.ndarray:
    n = samples(950)
    t = t_axis(n)
    f = np.where(t < 0.25, 150 * (45 / 150) ** (t / 0.25), 45.0)
    boom = (glide_sine(f) + 0.25 * glide_sine(2 * f)) * attack(expdec(n, 220), 3)
    rumble = lp(noise(n), 300) * expdec(n, 80)
    shimmer = np.zeros(n)
    taus = [450, 410, 370, 330, 290, 250]
    for r, g, tau in zip([1, 1.5, 2, 2.5, 3, 4], [0.20, 0.14, 0.11, 0.08, 0.06, 0.05], taus):
        shimmer += g * detuned_pair(1318.5 * r, n, 0.003, tau, a_ms=1)
    fade_in = np.clip((t - 0.12) / 0.15, 0, 1)
    shimmer *= fade_in * (1 + 0.3 * np.sin(2 * np.pi * 7 * t))
    return boom + 0.5 * rumble + shimmer


def reaction_pop() -> np.ndarray:
    n = samples(90)
    t = t_axis(n)
    f = np.where(t < 0.06, 400 + (900 - 400) * t / 0.06, 900.0)
    body = glide_sine(f) * attack(np.hanning(n), 3)
    return body + 0.2 * bp(noise(n), 1000, 3000) * expdec(n, 10)


SOUNDS = [
    ("card_slide", card_slide, 0.65),
    ("card_snap", card_snap, 0.85),
    ("card_flip", card_flip, 0.7),
    ("deal_riffle", deal_riffle, 0.6),
    ("stack_thud", stack_thud, 0.9),
    ("tap_select", tap_select, 0.3),
    ("button_press", button_press, 0.4),
    ("trump_chime", trump_chime, 0.55),
    ("my_turn_ding", my_turn_ding, 0.5),
    ("achievement_bell", achievement_bell, 0.6),
    ("win_fanfare", win_fanfare, 0.65),
    ("goat_moan", goat_moan, 0.6),
    ("shoha_impact", shoha_impact, 1.0),
    ("reaction_pop", reaction_pop, 0.45),
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for name, fn, mix in SOUNDS:
        size = write_wav(name, fn(), mix)
        total += size
        print(f"{name}.wav  {size / 1024:.1f} KB")
    print(f"total: {total / 1024:.1f} KB across {len(SOUNDS)} files")


if __name__ == "__main__":
    main()
