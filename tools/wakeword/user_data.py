"""Enregistrements de l'utilisateur (archive exportée par l'écran
« Entraîner Sentrix avec ma voix ») → caractéristiques d'entraînement.

La voix de l'utilisateur n'est jamais versionnée : l'archive reste hors du
dépôt, seuls le modèle et ses mesures y entrent.
"""

from __future__ import annotations

import io
import json
import zipfile

import numpy as np
import soundfile as sf

from augment import augment, augment_negative
from features import CLIP, SR, Features, windows


def load_zip(path: str) -> dict[str, list[np.ndarray]]:
    out: dict[str, list[np.ndarray]] = {"sentrix": [], "speech": [], "ambient": []}
    with zipfile.ZipFile(path) as z:
        manifest = json.loads(z.read("manifest.json"))
        for name in sorted(z.namelist()):
            kind = name.split("/")[0]
            if kind not in out or not name.endswith(".wav"):
                continue
            data, sr = sf.read(io.BytesIO(z.read(name)), dtype="float32")
            if data.ndim > 1:
                data = data.mean(axis=1)
            if sr != SR:
                from scipy.signal import resample_poly

                g = np.gcd(sr, SR)
                data = resample_poly(data, SR // g, sr // g).astype(np.float32)
            out[kind].append(data)
    print(f"  archive : {manifest.get('counts')} (application {manifest.get('app')})")
    return out


def trim_word(x: np.ndarray) -> np.ndarray:
    """Isole le mot dans un extrait de 2 s (énergie au-dessus de 10 % du maximum)."""
    frame = 160
    n = len(x) // frame
    if n == 0:
        return x
    e = np.sqrt(np.mean(x[: n * frame].reshape(n, frame) ** 2, axis=1))
    on = np.where(e > 0.1 * e.max())[0]
    if len(on) == 0:
        return x
    a, b = max(0, on[0] - 5), min(n, on[-1] + 6)
    return x[a * frame : b * frame]


def truncated(x: np.ndarray) -> bool:
    """Mot coupé au début (l'utilisateur a parlé avant le début réel de
    l'enregistrement) : forte énergie dans les 50 premières ms."""
    frame = 160
    n = len(x) // frame
    e = np.sqrt(np.mean(x[: n * frame].reshape(n, frame) ** 2, axis=1))
    return bool(e[1:5].max() >= 0.5 * e.max())


def user_features(path: str, feats: Features, rng: np.random.Generator, reps: int = 100, test_every: int = 3):
    """Positifs d'entraînement augmentés, positifs de test (jamais vus),
    négatifs (parole et bruit de l'utilisateur)."""
    d = load_zip(path)
    kept = [x for x in d["sentrix"] if not truncated(x)]
    print(f"  « Sentrix » coupés au début écartés : {len(d['sentrix']) - len(kept)}")
    words = [trim_word(x) for x in kept]
    test_idx = set(range(test_every - 1, len(words), test_every))
    train = [w for i, w in enumerate(words) if i not in test_idx]
    test = [w for i, w in enumerate(words) if i in test_idx]
    x_pos = []
    for w in train:
        for _ in range(reps):
            win = windows(feats.embed(augment(w, CLIP, rng, (0.80, 0.97))))
            if len(win):
                x_pos.append(win[-1])
    # Test : extraits de 3 s, mot à des positions variées, bruit de route.
    test_pos = [windows(feats.embed(augment(w, 3 * SR, rng, (0.63, 0.87)))) for w in test for _ in range(4)]
    negs = []
    for a in d["speech"] + d["ambient"]:
        for _ in range(4):
            negs.append(windows(feats.embed_long(augment_negative(a, rng)), stride=2))
    x_neg = np.concatenate(negs) if negs else np.zeros((0, 16, 96), np.float32)
    print(f"  voix de l'utilisateur : {len(train)} « Sentrix » d'entraînement (×{reps}), {len(test)} de test, {len(x_neg)} fenêtres négatives")
    return np.stack(x_pos).astype(np.float32), test_pos, x_neg.astype(np.float32)
