"""Augmentations : habitacle de voiture, bruits de route, voix parasites, micro de téléphone."""

from __future__ import annotations

import numpy as np
from scipy import signal

from features import SR


def _norm(x: np.ndarray) -> np.ndarray:
    return x / (np.sqrt(np.mean(x**2)) + 1e-9)


def car_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    """Bruit de roulage : bruit brun filtré + harmoniques moteur modulées."""
    brown = np.cumsum(rng.standard_normal(n))
    brown = signal.sosfilt(signal.butter(2, 20, "highpass", fs=SR, output="sos"), brown)
    t = np.arange(n) / SR
    f0 = rng.uniform(25, 90)
    wobble = 1 + 0.05 * np.sin(2 * np.pi * rng.uniform(0.1, 0.5) * t)
    engine = sum(np.sin(2 * np.pi * f0 * k * wobble * t + rng.uniform(0, 6.28)) / k for k in range(1, 5))
    wind = signal.sosfilt(signal.butter(2, [300, 2500], "bandpass", fs=SR, output="sos"), rng.standard_normal(n))
    mix = _norm(brown) + rng.uniform(0.2, 0.8) * _norm(engine) + rng.uniform(0.0, 0.6) * _norm(wind)
    return _norm(mix)


def pink_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    white = np.fft.rfft(rng.standard_normal(n))
    f = np.maximum(np.fft.rfftfreq(n), 1 / n)
    return _norm(np.fft.irfft(white / np.sqrt(f), n))


def room_ir(rng: np.random.Generator) -> np.ndarray:
    """Réponse impulsionnelle synthétique d'habitacle (RT60 50–350 ms)."""
    rt60 = rng.uniform(0.05, 0.35)
    n = int(rt60 * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / rt60)
    ir[0] = 1.0 / rng.uniform(0.3, 1.0)  # trajet direct
    return ir / np.max(np.abs(ir))


def phone_mic(x: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    hp = rng.uniform(60, 200)
    lp = rng.uniform(3500, 7600)
    return signal.sosfilt(signal.butter(2, [hp, lp], "bandpass", fs=SR, output="sos"), x)


def augment(
    speech: np.ndarray,
    length: int,
    rng: np.random.Generator,
    end_range: tuple[float, float],
    babble: list[np.ndarray] | None = None,
) -> np.ndarray:
    """Place [speech] (float, ±1) dans [length] échantillons, fin du mot dans
    [end_range] (fraction de la durée), puis habitacle, bruits et micro."""
    out = np.zeros(length)
    s = speech[: length - 1]
    end = int(rng.uniform(*end_range) * length)
    start = max(0, end - len(s))
    out[start : start + len(s)] = s[: length - start]
    if rng.random() < 0.6:
        out = signal.fftconvolve(out, room_ir(rng))[:length]
    out = _norm(out) * 10 ** (rng.uniform(-30, -12) / 20)  # niveau de voix
    level = np.sqrt(np.mean(out**2))
    r = rng.random()
    if r < 0.85:
        noise = car_noise(length, rng) if rng.random() < 0.7 else pink_noise(length, rng)
        snr = rng.uniform(0, 20)
        out = out + noise * level / 10 ** (snr / 20)
    if babble and rng.random() < 0.3:
        b = babble[rng.integers(len(babble))]
        if len(b) > length:
            o = rng.integers(len(b) - length)
            b = b[o : o + length]
            out = out + _norm(b) * level / 10 ** (rng.uniform(8, 20) / 20)
    out = phone_mic(out, rng)
    peak = np.max(np.abs(out)) + 1e-9
    if peak > 0.98:
        out = out / peak * 0.98
    return (out * 32767).astype(np.int16)
