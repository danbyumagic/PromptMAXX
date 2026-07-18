"""
export_numpy.py — convert the trained PyTorch checkpoint to a portable .npz.

This lets the model run at inference time with *only* numpy (see
generate_numpy.py) — no PyTorch needed on the target Mac. Handy because the
model is tiny; the whole thing is a few megabytes.

    python src/export_numpy.py
"""
import json
import os

import numpy as np
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")


def main():
    ckpt = torch.load(os.path.join(DATA, "model.pt"), map_location="cpu")
    sd = ckpt["model"]
    arrays = {k: v.float().numpy() for k, v in sd.items()}
    # tok_emb is tied to lm_head; make sure both are present for clarity
    if "tok_emb.weight" not in arrays and "lm_head.weight" in arrays:
        arrays["tok_emb.weight"] = arrays["lm_head.weight"]

    out = os.path.join(DATA, "model_weights.npz")
    np.savez(out, **arrays)
    with open(os.path.join(DATA, "model_config.json"), "w") as f:
        json.dump(ckpt["config"], f, indent=2)

    size_mb = os.path.getsize(out) / 1e6
    print(f"exported {len(arrays)} tensors -> {out} ({size_mb:.2f} MB)")
    print("config:", ckpt["config"])


if __name__ == "__main__":
    main()
