"""Essais d'entraînement rapides sur les caractéristiques exportées par la CI
(`train_sentrix.py --dump`), sans recalculer l'audio.

python experiment.py features.npz --variant base --variant small_dropout ...
Chaque variante est mesurée comme en CI : détection sur des voix jamais vues,
fausses activations par heure sur de la parole française réservée et sur la
validation openWakeWord (parole, musique, bruit).
"""

from __future__ import annotations

import argparse
import json
import time

import numpy as np
import torch
import torch.nn as nn

from train_sentrix import false_accepts, scores
from features import N_EMB, SR, STEP, windows


def mlp(hidden: int, layers: int, dropout: float) -> nn.Module:
    mods: list[nn.Module] = [nn.Flatten()]
    d = N_EMB * 96
    for _ in range(layers):
        mods += [nn.Linear(d, hidden), nn.LayerNorm(hidden), nn.ReLU()]
        if dropout:
            mods.append(nn.Dropout(dropout))
        d = hidden
    mods.append(nn.Linear(d, 1))
    return nn.Sequential(*mods)


VARIANTS = {
    # Référence : réglages de la première exécution CI.
    "base": dict(hidden=128, layers=2, dropout=0.0, wneg_max=20, steps=30000, acav_frac=0.25, wd=1e-4),
    "small_dropout": dict(hidden=64, layers=2, dropout=0.3, wneg_max=20, steps=20000, acav_frac=0.4, wd=1e-3),
    "small_dropout_wneg50": dict(hidden=64, layers=2, dropout=0.3, wneg_max=50, steps=20000, acav_frac=0.4, wd=1e-3),
    "tiny": dict(hidden=32, layers=1, dropout=0.2, wneg_max=30, steps=20000, acav_frac=0.4, wd=1e-3),
    "mid_acav": dict(hidden=96, layers=2, dropout=0.3, wneg_max=30, steps=30000, acav_frac=0.6, wd=1e-3),
}


def load(path: str):
    d = np.load(path, allow_pickle=True)
    f = lambda k: [np.asarray(x, np.float32) for x in d[k]]  # noqa: E731
    return {
        "x_pos": np.asarray(d["x_pos"], np.float32),
        "x_adv": np.asarray(d["x_adv"], np.float32),
        "x_speech": np.asarray(d["x_speech"], np.float32),
        "acav": np.asarray(d["acav"], np.float32),
        "oww_val": np.asarray(d["oww_val"], np.float32),
        "val_pos": f("val_pos"),
        "test_pos": f("test_pos"),
        "val_streams": f("val_streams"),
        "test_streams": f("test_streams"),
        "hours": d["hours"],
    }


def measure(model, pos, streams, hours, thr):
    pm = np.array([scores(model, w).max() if len(w) else 0.0 for w in pos])
    ss = [scores(model, windows(e)) for e in streams]
    return float((pm >= thr).mean()), false_accepts(ss, thr) / max(hours, 1e-9), pm, ss


def best_threshold(pm, ss, hours, max_fa=0.5):
    """Seuil le plus bas respectant la limite de fausses activations (validation)."""
    for t in np.round(np.arange(0.05, 1.0, 0.01), 2):
        if false_accepts(ss, t) / hours <= max_fa:
            return float(t), float((pm >= t).mean())
    return 0.99, float((pm >= 0.99).mean())


def run(data, name, cfg, seed=0):
    rng = np.random.default_rng(seed)
    torch.manual_seed(seed)
    model = mlp(cfg["hidden"], cfg["layers"], cfg["dropout"])
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=cfg["wd"])
    steps = cfg["steps"]
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=1e-3, total_steps=steps)
    bce = nn.BCEWithLogitsLoss(reduction="none")
    xp, xa, xs, xc = data["x_pos"], data["x_adv"], data["x_speech"], data["acav"]
    t0 = time.time()
    for step in range(1, steps + 1):
        bp, bn = 128, 384
        pos = xp[rng.integers(len(xp), size=bp)]
        n_ac = int(bn * cfg["acav_frac"]) if len(xc) else 0
        n_adv = bn // 8
        n_sp = bn - n_ac - n_adv
        parts = [xs[rng.integers(len(xs), size=n_sp)], xa[rng.integers(len(xa), size=n_adv)]]
        if n_ac:
            parts.append(xc[rng.integers(len(xc), size=n_ac)])
        xb = np.concatenate([pos, *parts]).astype(np.float32)
        yb = np.concatenate([np.ones(bp), np.zeros(len(xb) - bp)]).astype(np.float32)
        wneg = 1 + (cfg["wneg_max"] - 1) * min(1.0, step / (0.6 * steps))
        w = np.where(yb == 1, 1.0, wneg).astype(np.float32)
        loss = (bce(model(torch.from_numpy(xb))[:, 0], torch.from_numpy(yb)) * torch.from_numpy(w)).mean()
        opt.zero_grad()
        loss.backward()
        opt.step()
        sched.step()
    vh, th = float(data["hours"][0]), float(data["hours"][1])
    _, _, vpm, vss = measure(model, data["val_pos"], data["val_streams"], vh, 0.5)
    thr, vrec = best_threshold(vpm, vss, vh)
    trec, tfa, _, _ = measure(model, data["test_pos"], data["test_streams"], th, thr)
    oww = None
    if len(data["oww_val"]):
        s = scores(model, windows(data["oww_val"]))
        oww = false_accepts([s], thr) / (len(data["oww_val"]) * STEP / SR / 3600)
    res = {"variant": name, "threshold": thr, "val_recall": vrec, "test_recall": trec, "test_fa_h": tfa, "oww_fa_h": oww, "seconds": round(time.time() - t0)}
    print(json.dumps(res, ensure_ascii=False))
    return model, res


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("npz")
    ap.add_argument("--variant", action="append")
    a = ap.parse_args()
    data = load(a.npz)
    print({k: (v.shape if hasattr(v, "shape") else len(v)) for k, v in data.items()})
    for v in a.variant or list(VARIANTS):
        run(data, v, VARIANTS[v])
