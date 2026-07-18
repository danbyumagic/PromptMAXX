"""
generate_numpy.py — run the Solira model with numpy only (no PyTorch).

Loads the .npz produced by export_numpy.py and reimplements the forward pass
in ~40 lines of numpy. Perfect for a minimal local install on a Mac: the only
dependency is numpy. Same sampling options as generate.py.

    python src/export_numpy.py          # once, to create the .npz
    python src/generate_numpy.py --genre HISTORIA -n 200
"""
import argparse
import json
import os

import numpy as np

from tokenizer import BPETokenizer

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
GENRES = ["FRASE", "DIALOG", "HISTORIA", "SALU", "QA"]


def erf(x):
    # Abramowitz & Stegun 7.1.26 (max abs error ~1.5e-7), vectorised.
    t = 1.0 / (1.0 + 0.3275911 * np.abs(x))
    y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t
                - 0.284496736) * t + 0.254829592) * t * np.exp(-x * x)
    return np.sign(x) * y


def gelu(x):
    return 0.5 * x * (1.0 + erf(x / np.sqrt(2.0)))


def layernorm(x, w, b, eps=1e-5):
    mu = x.mean(-1, keepdims=True)
    var = x.var(-1, keepdims=True)
    return (x - mu) / np.sqrt(var + eps) * w + b


def softmax(x, axis=-1):
    x = x - x.max(axis=axis, keepdims=True)
    e = np.exp(x)
    return e / e.sum(axis=axis, keepdims=True)


class NumpyGPT:
    def __init__(self, npz_path, cfg_path):
        self.w = {k: v for k, v in np.load(npz_path).items()}
        self.cfg = json.load(open(cfg_path))
        self.n_layer = self.cfg["n_layer"]
        self.n_head = self.cfg["n_head"]
        self.n_embd = self.cfg["n_embd"]
        self.block = self.cfg["block_size"]

    def _linear(self, x, name):
        W = self.w[name + ".weight"]           # (out, in)
        y = x @ W.T
        b = self.w.get(name + ".bias")
        return y + b if b is not None else y

    def forward(self, idx):
        """idx: (T,) int array -> logits for the last position (vocab,)."""
        w = self.w
        T = len(idx)
        x = w["tok_emb.weight"][idx] + w["pos_emb.weight"][:T]   # (T, C)
        H, hd = self.n_head, self.n_embd // self.n_head
        for i in range(self.n_layer):
            p = f"blocks.{i}."
            h = layernorm(x, w[p + "ln_1.weight"], w[p + "ln_1.bias"])
            qkv = self._linear(h, p + "attn.c_attn")            # (T, 3C)
            q, k, v = np.split(qkv, 3, axis=-1)
            # split into heads: (H, T, hd)
            q = q.reshape(T, H, hd).transpose(1, 0, 2)
            k = k.reshape(T, H, hd).transpose(1, 0, 2)
            v = v.reshape(T, H, hd).transpose(1, 0, 2)
            att = q @ k.transpose(0, 2, 1) / np.sqrt(hd)         # (H, T, T)
            mask = np.triu(np.ones((T, T), dtype=bool), k=1)
            att = np.where(mask, -1e10, att)
            att = softmax(att, axis=-1)
            y = att @ v                                          # (H, T, hd)
            y = y.transpose(1, 0, 2).reshape(T, self.n_embd)
            x = x + self._linear(y, p + "attn.c_proj")
            h = layernorm(x, w[p + "ln_2.weight"], w[p + "ln_2.bias"])
            h = gelu(self._linear(h, p + "mlp.c_fc"))
            x = x + self._linear(h, p + "mlp.c_proj")
        x = layernorm(x, w["ln_f.weight"], w["ln_f.bias"])
        logits = x[-1] @ w["lm_head.weight"].T                  # (vocab,)
        return logits

    def generate(self, ids, n, temperature=0.9, top_k=40, rng=None):
        rng = rng or np.random.default_rng()
        ids = list(ids)
        for _ in range(n):
            cond = np.array(ids[-self.block:])
            logits = self.forward(cond) / max(temperature, 1e-6)
            if top_k:
                kth = np.sort(logits)[-min(top_k, len(logits))]
                logits = np.where(logits < kth, -np.inf, logits)
            probs = softmax(logits)
            ids.append(int(rng.choice(len(probs), p=probs)))
        return ids


def pretty(text):
    for tag in ("[FRASE]", "[QA]", "[DIALOG]", "[HISTORIA]", "[SALU]"):
        text = text.replace(tag, "\n" + tag)
    return text.replace(" — ", "\n  — ").strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", default=None)
    ap.add_argument("--genre", default=None, choices=GENRES)
    ap.add_argument("-n", "--num-tokens", type=int, default=120)
    ap.add_argument("--num-samples", type=int, default=4)
    ap.add_argument("--temperature", type=float, default=0.9)
    ap.add_argument("--top-k", type=int, default=40)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--npz", default=os.path.join(DATA, "model_weights.npz"))
    ap.add_argument("--config", default=os.path.join(DATA, "model_config.json"))
    ap.add_argument("--tokenizer", default=os.path.join(DATA, "tokenizer.json"))
    args = ap.parse_args()

    tok = BPETokenizer.load(args.tokenizer)
    gpt = NumpyGPT(args.npz, args.config)
    rng = np.random.default_rng(args.seed)
    print(f"# numpy backend  params(config)={gpt.cfg}\n")

    if args.prompt is not None:
        prompt = args.prompt
    elif args.genre is not None:
        prompt = f"[{args.genre}] "
    else:
        prompt = "[FRASE] "

    for _ in range(args.num_samples):
        out = gpt.generate(tok.encode(prompt), args.num_tokens,
                           args.temperature, args.top_k, rng)
        print(pretty(tok.decode(out)))
        print("-" * 60)


if __name__ == "__main__":
    main()
