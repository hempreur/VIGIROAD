"""Parité : caractéristiques calculées en flux (comme l'application Dart :
blocs de 1 280 échantillons + 480 de contexte) vs en une fois (entraînement)."""
import sys
import numpy as np
import torch
import experiment as ex
from features import Features, SR, windows as wins
from user_data import load_zip, truncated, trim_word
from augment import augment

class Stream:
    def __init__(self, f):
        self.f = f
        self.raw = np.zeros(480, np.int16)
        self.mel = np.ones((76, 32), np.float32)
        self.emb = []
    def push(self, block):
        x = np.concatenate([self.raw, block]).astype(np.float32)[None]
        out = self.f.mel_s.run(None, {"input": x})[0]
        m = np.squeeze(out).reshape(-1, 32) / 10 + 2
        self.raw = block[-480:]
        self.mel = np.concatenate([self.mel, m])[-76:]
        e = self.f.emb_s.run(None, {self.f.emb_in: self.mel[None, :, :, None].astype(np.float32)})[0].reshape(96)
        self.emb.append(e)

f = Features(f"{sys.argv[3]}/melspectrogram.onnx", f"{sys.argv[3]}/embedding_model.onnx")
model = ex.mlp(64, 2, 0.3); model.load_state_dict(torch.load("/tmp/claude-0/wwdata/focus_user.pt")); model.eval()
rng = np.random.default_rng(99)
d = load_zip(sys.argv[2])
kept = [x for x in d["sentrix"] if not truncated(x)]
test = [trim_word(w) for i, w in enumerate(kept) if i % 3 == 2]
pb, ps, diffs = [], [], []
for w in test:
    for _ in range(4):
        a = augment(w, 3 * SR, rng, (0.63, 0.87))
        batch = ex.scores(model, wins(f.embed(a)))
        s = Stream(f)
        for i in range(0, len(a) - 1279, 1280):
            s.push(a[i:i + 1280])
        e = np.array(s.emb)
        stream = ex.scores(model, wins(e)) if len(e) >= 16 else np.zeros(1)
        pb.append(batch); ps.append(stream)
        eb = f.embed(a)
        n = min(len(eb), len(e))
        diffs.append(np.abs(eb[-n:] - e[-n:]).mean() / (np.abs(eb[-n:]).mean() + 1e-9))
for p, t in ((3, 0.9995), (2, 0.9995), (3, 0.999), (3, 0.998)):
    print(f"confirmation {p}, seuil {t} : détection en une fois {ex.recall(pb, t, p):.3f}, en flux {ex.recall(ps, t, p):.3f}")
print(f"écart relatif moyen des plongements flux/une fois : {np.mean(diffs):.3%}")
