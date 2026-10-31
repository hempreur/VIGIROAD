"""Caractéristiques audio openWakeWord (melspectrogramme + plongements).

Même chaîne que l'application (lib/features/sentrix/data/wake_word_engine.dart) :
audio 16 kHz int16 -> melspectrogram.onnx (valeurs int16 brutes en float32,
sortie /10 + 2) -> fenêtres de 76 trames, pas de 8 -> embedding_model.onnx
(96 valeurs par pas de 80 ms). Le classifieur lit 16 plongements (1,28 s).
"""

from __future__ import annotations

import numpy as np
import onnxruntime as ort

SR = 16000
STEP = 1280  # 80 ms
N_EMB = 16  # plongements lus par le classifieur
CLIP = 32000  # 2 s : exactement 16 plongements


class Features:
    def __init__(self, mel_path: str, emb_path: str, threads: int = 4):
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = threads
        opts.inter_op_num_threads = 1
        self.mel_s = ort.InferenceSession(mel_path, opts, providers=["CPUExecutionProvider"])
        self.emb_s = ort.InferenceSession(emb_path, opts, providers=["CPUExecutionProvider"])
        self.emb_in = self.emb_s.get_inputs()[0].name

    def mel(self, audio: np.ndarray) -> np.ndarray:
        x = audio.astype(np.int16).astype(np.float32)[None]
        out = self.mel_s.run(None, {"input": x})[0]
        return np.squeeze(out).reshape(-1, 32) / 10 + 2

    def embed(self, audio: np.ndarray, batch: int = 512) -> np.ndarray:
        """Plongements (n, 96) d'un enregistrement, un toutes les 80 ms."""
        spec = self.mel(audio)
        if spec.shape[0] < 76:
            return np.zeros((0, 96), np.float32)
        starts = range(0, spec.shape[0] - 76 + 1, 8)
        wins = np.stack([spec[i : i + 76] for i in starts]).astype(np.float32)[..., None]
        outs = [self.emb_s.run(None, {self.emb_in: wins[i : i + batch]})[0] for i in range(0, len(wins), batch)]
        return np.concatenate(outs).reshape(-1, 96).astype(np.float32)

    def embed_long(self, audio: np.ndarray, chunk_s: float = 30.0) -> np.ndarray:
        """Enregistrement long découpé en tronçons (avec recouvrement de contexte)."""
        n = int(chunk_s * SR)
        ctx = 76 * 160  # contexte d'une fenêtre de plongement
        out = []
        for start in range(0, len(audio), n):
            seg = audio[max(0, start - ctx) : start + n]
            e = self.embed(seg)
            if start > 0:
                e = e[max(0, (min(start, ctx) // STEP)) :]
            out.append(e)
        return np.concatenate(out) if out else np.zeros((0, 96), np.float32)


def windows(emb: np.ndarray, stride: int = 1) -> np.ndarray:
    """Fenêtres de 16 plongements consécutifs (n, 16, 96)."""
    if len(emb) < N_EMB:
        return np.zeros((0, N_EMB, 96), np.float32)
    idx = np.arange(0, len(emb) - N_EMB + 1, stride)
    return np.stack([emb[i : i + N_EMB] for i in idx])
