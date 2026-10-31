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

from train_sentrix import scores


def false_accepts(stream_scores, thr: float, patience: int = 1, refractory: int = 25) -> int:
    """Activations : [patience] trames consécutives au-dessus du seuil, puis 2 s de garde."""
    n = 0
    for s in stream_scores:
        run, i = 0, 0
        while i < len(s):
            run = run + 1 if s[i] >= thr else 0
            if run >= patience:
                n += 1
                run = 0
                i += refractory
            else:
                i += 1
    return n


def detected(s: np.ndarray, thr: float, patience: int) -> bool:
    run = 0
    for v in s:
        run = run + 1 if v >= thr else 0
        if run >= patience:
            return True
    return False
from numpy.lib.stride_tricks import sliding_window_view

from features import N_EMB, SR, STEP


def windows(e: np.ndarray) -> np.ndarray:
    """Fenêtres glissantes sans copie (mémoire limitée)."""
    if len(e) < N_EMB:
        return np.zeros((0, N_EMB, 96), e.dtype)
    return sliding_window_view(e, (N_EMB, 96))[:, 0]


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
    # Avec seconde passe sur les négatifs qui trompent le modèle.
    "small_mined": dict(hidden=64, layers=2, dropout=0.3, wneg_max=20, steps=20000, acav_frac=0.4, wd=1e-3, mine=10000),
    "mid_mined": dict(hidden=96, layers=2, dropout=0.3, wneg_max=30, steps=25000, acav_frac=0.5, wd=1e-3, mine=15000),
}


def load(path: str):
    d = np.load(path, allow_pickle=True)
    f = lambda k: [np.asarray(x, np.float16) for x in d[k]]  # noqa: E731
    return {
        "x_pos": d["x_pos"],
        "x_adv": d["x_adv"],
        "x_speech": d["x_speech"],
        "acav": d["acav"],
        "oww_val": d["oww_val"],
        "val_pos": f("val_pos"),
        "test_pos": f("test_pos"),
        "val_streams": f("val_streams"),
        "test_streams": f("test_streams"),
        "hours": d["hours"],
    }


def pos_scores(model, pos):
    return [scores(model, w) if len(w) else np.zeros(1) for w in pos]


def recall(ps, thr, patience):
    return float(np.mean([detected(s, thr, patience) for s in ps]))


def best_threshold(ps, ss, hours, patience, max_fa=0.5):
    """Seuil le plus bas respectant la limite de fausses activations (validation)."""
    for t in np.round(np.arange(0.05, 1.0, 0.01), 2):
        if false_accepts(ss, t, patience) / hours <= max_fa:
            return float(t), recall(ps, t, patience)
    return 0.995, recall(ps, 0.995, patience)


def run(data, name, cfg, seed=0):
    rng = np.random.default_rng(seed)
    torch.manual_seed(seed)
    model = mlp(cfg["hidden"], cfg["layers"], cfg["dropout"])
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=cfg["wd"])
    steps = cfg["steps"]
    bce = nn.BCEWithLogitsLoss(reduction="none")
    xp, xa, xs, xc = data["x_pos"], data["x_adv"], data["x_speech"], data["acav"]
    t0 = time.time()
    hard = None
    mine = cfg.get("mine", 0)
    total = steps + mine
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=1e-3, total_steps=total)
    for step in range(1, total + 1):
        if step == steps + 1 and mine:
            # Négatifs les plus trompeurs (3 % des scores les plus hauts).
            pool = np.concatenate([xs, xc]) if len(xc) else xs
            sc = scores(model, pool)
            hard = pool[np.argsort(sc)[-max(1000, len(pool) * 3 // 100):]]
            print(f"   {name} : {len(hard)} négatifs difficiles, score min {np.sort(sc)[-len(hard)]:.3f}", flush=True)
        bp, bn = 128, 384
        pos = xp[rng.integers(len(xp), size=bp)]
        n_ac = int(bn * cfg["acav_frac"]) if len(xc) else 0
        n_adv = bn // 8
        n_sp = bn - n_ac - n_adv
        parts = [xs[rng.integers(len(xs), size=n_sp)], xa[rng.integers(len(xa), size=n_adv)]]
        if hard is not None:
            parts[0] = parts[0][: n_sp // 2]
            parts.append(hard[rng.integers(len(hard), size=n_sp - n_sp // 2)])
        if n_ac:
            parts.append(xc[rng.integers(len(xc), size=n_ac)])
        xb = np.concatenate([pos, *parts]).astype(np.float32)
        yb = np.concatenate([np.ones(bp), np.zeros(len(xb) - bp)]).astype(np.float32)
        wneg = 1 + (cfg["wneg_max"] - 1) * min(1.0, step / (0.6 * total))
        w = np.where(yb == 1, 1.0, wneg).astype(np.float32)
        loss = (bce(model(torch.from_numpy(xb))[:, 0], torch.from_numpy(yb)) * torch.from_numpy(w)).mean()
        opt.zero_grad()
        loss.backward()
        opt.step()
        sched.step()
    return model, report(model, data, name, t0)


def report(model, data, name, t0=None):
    vh, th = float(data["hours"][0]), float(data["hours"][1])
    vps, vss = pos_scores(model, data["val_pos"]), [scores(model, windows(e)) for e in data["val_streams"]]
    tps, tss = pos_scores(model, data["test_pos"]), [scores(model, windows(e)) for e in data["test_streams"]]
    oww_s = scores(model, windows(data["oww_val"])) if len(data["oww_val"]) else None
    oww_h = len(data["oww_val"]) * STEP / SR / 3600
    out = []
    for patience in (1, 2, 3):
        thr, vrec = best_threshold(vps, vss, vh, patience)
        res = {
            "variant": name,
            "patience": patience,
            "threshold": thr,
            "val_recall": round(vrec, 3),
            "test_recall": round(recall(tps, thr, patience), 3),
            "test_fa_h": round(false_accepts(tss, thr, patience) / th, 2),
            "oww_fa_h": round(false_accepts([oww_s], thr, patience) / oww_h, 2) if oww_s is not None else None,
            "user_recall": round(recall(pos_scores(model, data["user_pos"]), thr, patience), 3) if data.get("user_pos") else None,
            "seconds": round(time.time() - t0) if t0 else None,
        }
        print(json.dumps(res, ensure_ascii=False), flush=True)
        out.append(res)
    return out


def add_user(data, zip_path: str, work: str):
    """Ajoute la voix de l'utilisateur : positifs d'entraînement, négatifs,
    et un jeu de test séparé (`user_pos`)."""
    from features import Features
    from user_data import user_features

    feats = Features(f"{work}/melspectrogram.onnx", f"{work}/embedding_model.onnx")
    xp, test_pos, xn = user_features(zip_path, feats, np.random.default_rng(99))
    # Les « Sentrix » de l'utilisateur pèsent autant que toutes les voix de synthèse.
    reps = max(1, len(data["x_pos"]) // max(1, len(xp)) // 2)
    data["x_pos"] = np.concatenate([np.asarray(data["x_pos"], np.float32), np.repeat(xp, reps, axis=0)])
    data["x_adv"] = np.concatenate([np.asarray(data["x_adv"], np.float32), xn])
    data["user_pos"] = test_pos
    return data


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("npz")
    ap.add_argument("--variant", action="append")
    ap.add_argument("--user-zip", help="archive « Entraîner Sentrix » de l'utilisateur")
    ap.add_argument("--work", default="work", help="dossier des modèles melspectrogram/embedding")
    a = ap.parse_args()
    data = load(a.npz)
    if a.user_zip:
        data = add_user(data, a.user_zip, a.work)
    print({k: (v.shape if hasattr(v, "shape") else len(v)) for k, v in data.items()})
    for v in a.variant or list(VARIANTS):
        run(data, v, VARIANTS[v])
