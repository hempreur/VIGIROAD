"""Variantes centrées sur la voix de l'utilisateur ; grille seuil × confirmation."""
import json, sys, time
import numpy as np
import torch
import experiment as ex

data = ex.load(sys.argv[1])
data = ex.add_user(data, sys.argv[2], sys.argv[3])
n_user = len(data["x_pos"]) - 13320  # positifs utilisateur ajoutés en fin
tts = data["x_pos"][:13320]
user = data["x_pos"][13320:]

def grid(model, name):
    vh, th = float(data["hours"][0]), float(data["hours"][1])
    ups = ex.pos_scores(model, data["user_pos"])
    tss = [ex.scores(model, ex.windows(e)) for e in data["test_streams"]]
    vss = [ex.scores(model, ex.windows(e)) for e in data["val_streams"]]
    oww = ex.scores(model, ex.windows(data["oww_val"]))
    oh = len(data["oww_val"]) * 1280 / 16000 / 3600
    for p in (2, 3, 4, 5):
        for t in (0.99, 0.995, 0.998, 0.999, 0.9995, 0.9998):
            r = {"variant": name, "patience": p, "threshold": t,
                 "user_recall": round(ex.recall(ups, t, p), 3),
                 "fr_fa_h_val": round(ex.false_accepts(vss, t, p) / vh, 2),
                 "fr_fa_h_test": round(ex.false_accepts(tss, t, p) / th, 2),
                 "oww_fa_h": round(ex.false_accepts([oww], t, p) / oh, 2)}
            print(json.dumps(r), flush=True)

for name, frac_user, acav, hidden in [("focus_user", 0.75, 0.5, 64), ("focus_user_acav", 0.75, 0.7, 64), ("focus_user_mid", 0.6, 0.6, 96)]:
    k = int(len(user) * (1 - frac_user) / frac_user)
    rng = np.random.default_rng(1)
    data["x_pos"] = np.concatenate([user, tts[rng.choice(len(tts), size=min(k, len(tts)), replace=False)]])
    cfg = dict(hidden=hidden, layers=2, dropout=0.3, wneg_max=30, steps=20000, acav_frac=acav, wd=1e-3, mine=10000)
    t0 = time.time()
    model, _ = ex.run(data, name, cfg)
    grid(model, name)
    torch.save(model.state_dict(), f"/tmp/claude-0/wwdata/{name}.pt")
    print(f"   {name} : {time.time()-t0:.0f} s", flush=True)
