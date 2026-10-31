"""Entraînement et mesure du mot d'activation « Sentrix » (openWakeWord).

Étapes :
  1. voix : synthèse de « Sentrix » par des voix Piper françaises (≈ 130
     locuteurs), séparées en entraînement / validation / test par locuteur ;
  2. négatifs : parole française réelle (Multilingual LibriSpeech, CC BY 4.0),
     2 000 h de parole, musique et bruit (caractéristiques openWakeWord),
     mots proches (« centre », « sentir »…) et phrases de l'application
     (consignes de guidage, réponses de SENTRIX) ;
  3. augmentations : habitacle, bruit de route, voix parasites, micro ;
  4. entraînement d'un petit réseau sur 16 plongements (1,28 s) ;
  5. mesure sur des voix jamais vues et sur des heures de parole réservées :
     taux de détection et fausses activations par heure ; seuil choisi sur
     la validation, chiffres publiés sur le test (docs/WAKE_WORD.md).

Usage : python train_sentrix.py --out out/          (CI)
        python train_sentrix.py --out out/ --selftest   (vérification rapide, données factices)
"""

from __future__ import annotations

import argparse
import io
import json
import os
import random
import time
from pathlib import Path

import numpy as np

from augment import augment
from features import CLIP, N_EMB, SR, STEP, Features, windows

FEATURE_MODELS = {
    "melspectrogram.onnx": "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/melspectrogram.onnx",
    "embedding_model.onnx": "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/embedding_model.onnx",
}

VOICES = [  # (chemin dans rhasspy/piper-voices, rôle)
    ("fr/fr_FR/mls/medium/fr_FR-mls-medium", "multi"),
    ("fr/fr_FR/upmc/medium/fr_FR-upmc-medium", "train"),
    ("fr/fr_FR/siwis/medium/fr_FR-siwis-medium", "train"),
    ("fr/fr_FR/mls_1840/low/fr_FR-mls_1840-low", "val"),
    ("fr/fr_FR/tom/medium/fr_FR-tom-medium", "test"),
    ("fr/fr_FR/gilles/low/fr_FR-gilles-low", "test"),
]

# Prononciations : française (« sɑ̃tʁiks ») surtout, et à l'anglaise.
POSITIVE_TEXTS = ["Sentrix", "Sentrix !", "Sentrix ?", "Sentrix.", "Sentrix,", "Senntrix", "Sène trix"]
POSITIVE_WEIGHTS = [4, 2, 2, 2, 1, 2, 1]

ADVERSARIAL = [
    "centre", "le centre-ville", "sentir", "ça sent bon", "il s'entraîne", "Sandrine", "matrice",
    "Astérix", "Obélix", "Félix", "électrique", "centrale", "sans tri", "cent trente", "sentinelle",
    "Patrick", "attractions", "s'entretient", "sentier", "centrifuge", "cendrier", "Béatrice",
    "c'est entre nous", "trente-six", "sans trique", "extrême", "Cédric", "sanctions", "sans risque",
]
APP_PHRASES = [
    "Dans 300 mètres, tournez à droite.", "Tournez à gauche sur la rue de Rivoli.", "Continuez tout droit.",
    "Au rond-point, prenez la deuxième sortie.", "Prenez la sortie 12 en direction de Lyon.",
    "Itinéraire recalculé.", "Vous êtes arrivé à destination.", "Guidage démarré, arrivée prévue à 15 heures.",
    "Attention, accident sur la N20 dans 2 kilomètres.", "Travaux sur l'A6 dans 600 mètres.",
    "Alerte. Plaque A A 1 2 3 B B. Véhicule signalé.", "Lecture des plaques arrêtée.",
    "Je n'ai pas compris. Dites aide pour connaître les commandes.", "Aucune perturbation signalée sur votre itinéraire.",
    "Je vous écoute.", "Le trafic est indisponible pour le moment.",
]
GENERAL = [
    "Bonjour, comment allez-vous aujourd'hui ?", "On s'arrête à la prochaine station-service.",
    "Tu peux mettre un peu de musique ?", "Il fait vraiment beau ce matin.", "On sera en retard de dix minutes.",
    "Appelle maman quand on arrive.", "La réunion commence à quatorze heures trente.",
    "Regarde, il y a des bouchons devant.", "Je pense qu'on devrait prendre l'autoroute.",
    "Le restaurant ferme à vingt-deux heures.", "Les enfants dorment à l'arrière.",
]


# --------------------------------------------------------------------------- téléchargements


def fetch(url: str, dest: Path) -> Path:
    import urllib.request

    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(url, dest)
    return dest


def hf(repo: str, filename: str, repo_type: str = "model") -> Path:
    from huggingface_hub import hf_hub_download

    return Path(hf_hub_download(repo_id=repo, filename=filename, repo_type=repo_type))


# --------------------------------------------------------------------------- synthèse


class Voice:
    def __init__(self, path: str):
        from piper import PiperVoice

        model = hf("rhasspy/piper-voices", path + ".onnx")
        cfg = hf("rhasspy/piper-voices", path + ".onnx.json")
        self.voice = PiperVoice.load(str(model), config_path=str(cfg))
        meta = json.loads(Path(cfg).read_text())
        self.sr = int(meta["audio"]["sample_rate"])
        self.speakers = int(meta.get("num_speakers", 1))

    def say(self, text: str, speaker: int | None, length: float, noise: float, noise_w: float) -> np.ndarray:
        from scipy.signal import resample_poly

        v = self.voice
        try:  # piper-tts >= 1.3
            from piper import SynthesisConfig

            syn = SynthesisConfig(speaker_id=speaker, length_scale=length, noise_scale=noise, noise_w_scale=noise_w)
            audio = np.concatenate([c.audio_int16_array for c in v.synthesize(text, syn_config=syn)])
        except ImportError:  # piper-tts 1.2
            raw = b"".join(
                v.synthesize_stream_raw(text, speaker_id=speaker, length_scale=length, noise_scale=noise, noise_w=noise_w)
            )
            audio = np.frombuffer(raw, dtype=np.int16)
        x = audio.astype(np.float64) / 32768
        if self.sr != SR:
            g = np.gcd(self.sr, SR)
            x = resample_poly(x, SR // g, self.sr // g)
        # Retire les silences de début et de fin.
        idx = np.where(np.abs(x) > 0.02 * (np.max(np.abs(x)) + 1e-9))[0]
        x = x[idx[0] : idx[-1] + 1] if len(idx) else x
        return x.astype(np.float32)


def speaker_split(n: int) -> dict[str, list[int]]:
    """Locuteurs de la voix multi-locuteurs : 70 % entraînement, 15 % validation, 15 % test."""
    ids = list(range(n))
    random.Random(7).shuffle(ids)
    a, b = int(n * 0.7), int(n * 0.85)
    return {"train": ids[:a], "val": ids[a:b], "test": ids[b:]}


def synth_set(voices, texts, weights, per_speaker, rng):
    """{split: [audio float]} pour une liste de textes."""
    out = {"train": [], "val": [], "test": []}
    for path, role in voices:
        try:
            v = Voice(path)
        except Exception as e:  # voix absente du dépôt : on continue sans elle
            print(f"  voix ignorée {path} : {e}")
            continue
        plan = speaker_split(v.speakers) if role == "multi" else {role: [None] * max(1, v.speakers)}
        if role != "multi" and v.speakers > 1:
            plan = {role: list(range(v.speakers))}
        for split, spk in plan.items():
            reps = per_speaker if role == "multi" else per_speaker * 8
            for s in spk:
                for _ in range(reps):
                    t = rng.choice(texts, p=np.array(weights) / sum(weights)) if weights else rng.choice(texts)
                    out[split].append(
                        v.say(str(t), s, rng.uniform(0.75, 1.35), rng.uniform(0.4, 0.9), rng.uniform(0.5, 1.0))
                    )
        print(f"  {path} : {v.speakers} locuteur(s), total {sum(len(x) for x in out.values())} extraits")
    return out


# --------------------------------------------------------------------------- parole réelle


def mls_audio(split: str, max_hours: float, shard: int = 0):
    """Parole française réelle (Multilingual LibriSpeech, CC BY 4.0), lue au
    fil de l'eau (float32) : 30 h en mémoire dépasseraient la RAM de la CI."""
    import pyarrow.parquet as pq
    import soundfile as sf

    name = f"french/{split}-{shard:05d}-of-{34 if split == 'train' else 1:05d}.parquet"
    pf = pq.ParquetFile(hf("facebook/multilingual_librispeech", name, "dataset"))
    total, n = 0.0, 0
    for batch in pf.iter_batches(batch_size=64, columns=["audio"]):
        for cell in batch.column(0).to_pylist():
            data, sr = sf.read(io.BytesIO(cell["bytes"]), dtype="float32")
            if data.ndim > 1:
                data = data.mean(axis=1)
            if sr != SR:
                from scipy.signal import resample_poly

                g = np.gcd(sr, SR)
                data = resample_poly(data, SR // g, sr // g).astype(np.float32)
            yield data
            n += 1
            total += len(data) / SR / 3600
            if total >= max_hours:
                print(f"  MLS {split} : {total:.1f} h, {n} enregistrements  (mémoire {rss_gb():.1f} Go)")
                return
    print(f"  MLS {split} : {total:.1f} h, {n} enregistrements  (mémoire {rss_gb():.1f} Go)")


def rss_gb() -> float:
    try:
        import resource

        return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e6
    except Exception:
        return 0.0


# --------------------------------------------------------------------------- modèle


def build_model():
    import torch.nn as nn

    return nn.Sequential(
        nn.Flatten(),
        nn.Linear(N_EMB * 96, 128),
        nn.LayerNorm(128),
        nn.ReLU(),
        nn.Linear(128, 128),
        nn.LayerNorm(128),
        nn.ReLU(),
        nn.Linear(128, 1),
    )


def scores(model, x: np.ndarray, batch: int = 4096) -> np.ndarray:
    import torch

    model.eval()
    out = []
    with torch.no_grad():
        for i in range(0, len(x), batch):
            out.append(torch.sigmoid(model(torch.from_numpy(np.asarray(x[i : i + batch], np.float32)))).numpy()[:, 0])
    model.train()
    return np.concatenate(out) if out else np.zeros(0)


def false_accepts(stream_scores: list[np.ndarray], thr: float, refractory: int = 25) -> int:
    """Activations sur des flux continus (une par épisode, 2 s de garde)."""
    n = 0
    for s in stream_scores:
        i = 0
        while i < len(s):
            if s[i] >= thr:
                n += 1
                i += refractory
            else:
                i += 1
    return n


def evaluate(model, pos_windows: list[np.ndarray], neg_streams: list[np.ndarray], hours: float, thresholds):
    """Détection : score max sur les fenêtres de chaque extrait positif.
    Fausses activations par heure sur des flux de parole/bruit continus."""
    pos_max = np.array([scores(model, w).max() if len(w) else 0.0 for w in pos_windows])
    stream_s = [scores(model, windows(e)) for e in neg_streams]
    res = []
    for t in thresholds:
        res.append(
            {
                "threshold": float(t),
                "recall": float((pos_max >= t).mean()) if len(pos_max) else 0.0,
                "fa_per_hour": false_accepts(stream_s, t) / max(hours, 1e-9),
            }
        )
    return res


# --------------------------------------------------------------------------- pipeline


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="out")
    ap.add_argument("--work", default="work")
    ap.add_argument("--selftest", action="store_true", help="données factices, quelques secondes")
    ap.add_argument("--steps", type=int, default=30000)
    ap.add_argument("--per-speaker", type=int, default=40)
    ap.add_argument("--mls-hours", type=float, default=30.0)
    ap.add_argument("--acav", action="store_true", help="négatifs openWakeWord 2 000 h (17 Go)")
    args = ap.parse_args()

    out, work = Path(args.out), Path(args.work)
    out.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(1234)
    t0 = time.time()

    for name, url in FEATURE_MODELS.items():
        fetch(url, work / name)
    feats = Features(str(work / "melspectrogram.onnx"), str(work / "embedding_model.onnx"), threads=os.cpu_count() or 4)

    # 1. Voix et négatifs audio --------------------------------------------------------
    if args.selftest:
        def fake(n, base):  # sons factices : « mot » = glissando, négatifs = bruit
            return [np.sin(2 * np.pi * (base + 300 * np.linspace(0, 1, 9000)) * np.arange(9000) / SR) * 0.5 for _ in range(n)]

        pos = {"train": fake(60, 400), "val": fake(15, 400), "test": fake(15, 400)}
        adv = {"train": fake(40, 900), "val": [], "test": []}
        def speech(n):
            return (rng.standard_normal(SR * 20).astype(np.float32) * 0.1 for _ in range(n))

        speech_train, speech_val, speech_test = speech(3), speech(2), speech(2)
    else:
        print("1. Synthèse des voix")
        pos = synth_set(VOICES, POSITIVE_TEXTS, POSITIVE_WEIGHTS, args.per_speaker, rng)
        adv = synth_set(VOICES[:3], ADVERSARIAL + APP_PHRASES + GENERAL, None, max(4, args.per_speaker // 4), rng)
        speech_train = mls_audio("train", args.mls_hours)
        speech_val = mls_audio("dev", 4.0)
        speech_test = mls_audio("test", 8.0)
    print(f"   positifs : { {k: len(v) for k, v in pos.items()} }, adverses : {len(adv['train'])}  ({time.time()-t0:.0f} s)")

    # 2. Caractéristiques -------------------------------------------------------------
    print("2. Parole réelle et plongements (au fil de l'eau)")
    # Négatifs : plongements de chaque enregistrement, audio aussitôt libéré ;
    # quelques extraits gardés comme voix parasites pour les augmentations.
    babble: list[np.ndarray] = []
    speech_windows = []
    for a in speech_train:
        if len(babble) < 200:
            babble.append(a[: SR * 15].copy())
        g = 10 ** (rng.uniform(-20, 0) / 20)
        e = feats.embed_long((a * 32767 * g).clip(-32767, 32767).astype(np.int16))
        if len(e) >= N_EMB:
            speech_windows.append(windows(e, stride=4).astype(np.float16))
    x_speech = np.concatenate(speech_windows)
    del speech_windows

    def streams(audios):
        out, secs = [], 0.0
        for a in audios:
            secs += len(a) / SR
            out.append(feats.embed_long((a * 32767).clip(-32767, 32767).astype(np.int16)))
        return out, secs / 3600

    val_streams, val_h = streams(speech_val)
    test_streams, test_h = streams(speech_test)
    print(f"   x_speech {x_speech.shape}, validation {val_h:.2f} h, test {test_h:.2f} h  (mémoire {rss_gb():.1f} Go, {time.time()-t0:.0f} s)")

    def pos_feats(clips, reps):
        xs = []
        for c in clips:
            for _ in range(reps):
                a = augment(c, CLIP, rng, (0.80, 0.97), babble)
                w = windows(feats.embed(a))
                if len(w):
                    xs.append(w[-1])
        return np.stack(xs).astype(np.float32)

    def pos_eval(clips):
        # 3 s, fin du mot entre 1,9 et 2,6 s : le flux est lu à toutes les positions.
        return [windows(feats.embed(augment(c, int(3 * SR), rng, (0.63, 0.87), babble))) for c in clips]

    x_pos = pos_feats(pos["train"], 3)
    x_adv = np.concatenate([windows(feats.embed(augment(c, CLIP, rng, (0.5, 0.97), babble)))[-4:] for c in adv["train"]])
    val_pos, test_pos = pos_eval(pos["val"]), pos_eval(pos["test"])
    acav = None
    oww_val = None
    if args.acav and not args.selftest:
        print("   négatifs openWakeWord (ACAV100M, 2 000 h) et validation openWakeWord")
        acav = np.load(hf("davidscripka/openwakeword_features", "openwakeword_features_ACAV100M_2000_hrs_16bit.npy", "dataset"), mmap_mode="r")
        oww_val = np.load(hf("davidscripka/openwakeword_features", "validation_set_features.npy", "dataset"))
    print(f"   x_pos {x_pos.shape}, x_adv {x_adv.shape}, x_speech {x_speech.shape}  (mémoire {rss_gb():.1f} Go, {time.time()-t0:.0f} s)")

    # 3. Entraînement -----------------------------------------------------------------
    import torch

    torch.manual_seed(0)
    model = build_model()
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=1e-4)
    steps = 200 if args.selftest else args.steps
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=1e-3, total_steps=steps)
    bce = torch.nn.BCEWithLogitsLoss(reduction="none")
    thresholds = np.round(np.arange(0.05, 1.0, 0.05), 2)
    best, best_state = None, None
    print("3. Entraînement")
    for step in range(1, steps + 1):
        bp, bn = 128, 384
        parts = [x_speech[rng.integers(len(x_speech), size=bn // 2)], x_adv[rng.integers(len(x_adv), size=bn // 4)]]
        if acav is not None:
            parts.append(np.asarray(acav[np.sort(rng.integers(len(acav), size=bn - bn // 2 - bn // 4))], np.float32))
        else:
            parts.append(x_speech[rng.integers(len(x_speech), size=bn - bn // 2 - bn // 4)])
        xb = np.concatenate([x_pos[rng.integers(len(x_pos), size=bp)], *parts]).astype(np.float32)
        yb = np.concatenate([np.ones(bp), np.zeros(len(xb) - bp)]).astype(np.float32)
        # Poids des négatifs croissant : on resserre les fausses activations au fil de l'entraînement.
        wneg = 1 + 19 * min(1.0, step / (0.6 * steps))
        w = np.where(yb == 1, 1.0, wneg).astype(np.float32)
        logits = model(torch.from_numpy(xb))[:, 0]
        loss = (bce(logits, torch.from_numpy(yb)) * torch.from_numpy(w)).mean()
        opt.zero_grad()
        loss.backward()
        opt.step()
        sched.step()
        if step % max(1, steps // 15) == 0 or step == steps:
            res = evaluate(model, val_pos, val_streams, val_h, thresholds)
            # Meilleur rappel avec au plus 0,5 fausse activation/heure en validation.
            ok = [r for r in res if r["fa_per_hour"] <= 0.5]
            cand = max(ok, key=lambda r: (r["recall"], r["threshold"])) if ok else None
            print(f"   pas {step}: perte {loss.item():.4f}, validation {cand}")
            if cand and (best is None or cand["recall"] > best["recall"]):
                best = {**cand, "step": step}
                best_state = {k: v.clone() for k, v in model.state_dict().items()}
    if best_state is None:
        best_state = model.state_dict()
        best = {"threshold": 0.9, "recall": 0.0, "fa_per_hour": None, "step": steps}
    model.load_state_dict(best_state)

    # 4. Mesures sur le test (voix et heures jamais vues) ------------------------------
    print("4. Mesures")
    thr = best["threshold"]
    test = evaluate(model, test_pos, test_streams, test_h, thresholds)
    oww = None
    if oww_val is not None:
        s = scores(model, windows(np.asarray(oww_val, np.float32)))
        oww_h = len(oww_val) * STEP / SR / 3600
        oww = {"hours": oww_h, "fa_per_hour": false_accepts([s], thr) / oww_h}
    at = next(r for r in test if r["threshold"] == thr)
    metrics = {
        "threshold": thr,
        "validation": best,
        "test": {"recall": at["recall"], "fa_per_hour_fr_speech": at["fa_per_hour"], "fr_speech_hours": test_h, "positives": len(test_pos)},
        "openwakeword_validation": oww,
        "curve_test": test,
        "data": {
            "positives_train": int(len(x_pos)),
            "adversarial": int(len(x_adv)),
            "speech_windows": int(len(x_speech)),
            "acav": bool(acav is not None),
        },
        "selftest": args.selftest,
        "seconds": round(time.time() - t0),
    }
    (out / "metrics.json").write_text(json.dumps(metrics, indent=2, ensure_ascii=False))
    print(json.dumps(metrics["test"], indent=2))

    # 5. Export ONNX (sortie = probabilité) ---------------------------------------------
    import torch.nn as nn

    full = nn.Sequential(model, nn.Sigmoid()).eval()
    torch.onnx.export(
        full,
        torch.zeros(1, N_EMB, 96),
        out / "sentrix.onnx",
        input_names=["input"],
        output_names=["score"],
        dynamic_axes={"input": {0: "batch"}, "score": {0: "batch"}},
        opset_version=13,
        dynamo=False,
    )
    import onnxruntime as ort

    check = ort.InferenceSession(str(out / "sentrix.onnx")).run(None, {"input": np.asarray(test_pos[0][-1:], np.float32)})[0]
    print(f"   export vérifié : score {float(check[0, 0]):.3f}  ({time.time()-t0:.0f} s)")
    for name in FEATURE_MODELS:
        (out / name).write_bytes((work / name).read_bytes())


if __name__ == "__main__":
    main()
