"""
train.py — train the tiny Solira GPT.

Runs on Apple-silicon MPS, CPU, or CUDA (auto-detected). Encodes the corpus
with the trained tokenizer (cached to data/*.bin), then optimises with AdamW
and a warmup+cosine schedule, printing validation loss and a live text sample
every so often. Saves a checkpoint to data/model.pt.

    python src/train.py                 # sensible defaults (~1.1M params)
    python src/train.py --max-steps 6000 --device mps
"""
import argparse
import math
import os
import time
from dataclasses import asdict

import numpy as np
import torch

from model import GPT, GPTConfig
from tokenizer import BPETokenizer

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")


def pick_device(requested):
    if requested and requested != "auto":
        return requested
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def load_tokens(tok, txt_path, bin_path):
    """Encode a text file to a uint16 token array, cached on disk."""
    if os.path.exists(bin_path) and os.path.getmtime(bin_path) >= os.path.getmtime(txt_path):
        return np.fromfile(bin_path, dtype=np.uint16)
    text = open(txt_path, encoding="utf-8").read()
    ids = np.array(tok.encode(text), dtype=np.uint16)
    ids.tofile(bin_path)
    return ids


def get_batch(data, block, batch, device):
    ix = torch.randint(len(data) - block - 1, (batch,))
    x = torch.stack([torch.from_numpy(data[i:i + block].astype(np.int64)) for i in ix])
    y = torch.stack([torch.from_numpy(data[i + 1:i + 1 + block].astype(np.int64)) for i in ix])
    return x.to(device), y.to(device)


@torch.no_grad()
def estimate_loss(model, splits, block, batch, device, iters):
    model.eval()
    out = {}
    for name, data in splits.items():
        losses = torch.zeros(iters)
        for k in range(iters):
            x, y = get_batch(data, block, batch, device)
            _, loss = model(x, y)
            losses[k] = loss.item()
        out[name] = losses.mean().item()
    model.train()
    return out


def lr_at(step, warmup, max_steps, lr, min_lr):
    if step < warmup:
        return lr * (step + 1) / warmup
    if step > max_steps:
        return min_lr
    ratio = (step - warmup) / max(1, max_steps - warmup)
    coeff = 0.5 * (1.0 + math.cos(math.pi * ratio))
    return min_lr + coeff * (lr - min_lr)


def sample(model, tok, device, prompt="[FRASE] ", n=80, temperature=0.9, top_k=40):
    ids = tok.encode(prompt)
    x = torch.tensor([ids], dtype=torch.long, device=device)
    out = model.generate(x, n, temperature=temperature, top_k=top_k)[0].tolist()
    return tok.decode(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-steps", type=int, default=3500)
    ap.add_argument("--batch-size", type=int, default=32)
    ap.add_argument("--block-size", type=int, default=256)
    ap.add_argument("--n-layer", type=int, default=5)
    ap.add_argument("--n-head", type=int, default=4)
    ap.add_argument("--n-embd", type=int, default=128)
    ap.add_argument("--dropout", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=3e-3)
    ap.add_argument("--min-lr", type=float, default=3e-4)
    ap.add_argument("--warmup", type=int, default=200)
    ap.add_argument("--weight-decay", type=float, default=0.1)
    ap.add_argument("--grad-clip", type=float, default=1.0)
    ap.add_argument("--eval-interval", type=int, default=250)
    ap.add_argument("--eval-iters", type=int, default=50)
    ap.add_argument("--device", default="auto")
    ap.add_argument("--seed", type=int, default=1337)
    ap.add_argument("--out", default=os.path.join(DATA, "model.pt"))
    args = ap.parse_args()

    torch.manual_seed(args.seed)
    torch.set_num_threads(os.cpu_count() or 1)
    device = pick_device(args.device)
    print(f"device: {device}  threads: {torch.get_num_threads()}")

    tok = BPETokenizer.load(os.path.join(DATA, "tokenizer.json"))
    train_data = load_tokens(tok, os.path.join(DATA, "corpus.txt"),
                             os.path.join(DATA, "train.bin"))
    val_data = load_tokens(tok, os.path.join(DATA, "val.txt"),
                           os.path.join(DATA, "val.bin"))
    splits = {"train": train_data, "val": val_data}
    print(f"tokens: train={len(train_data):,}  val={len(val_data):,}  vocab={tok.vocab_size}")

    cfg = GPTConfig(vocab_size=tok.vocab_size, block_size=args.block_size,
                    n_layer=args.n_layer, n_head=args.n_head,
                    n_embd=args.n_embd, dropout=args.dropout)
    model = GPT(cfg).to(device)
    print(f"parameters: {model.num_params():,}")

    optim = torch.optim.AdamW(model.parameters(), lr=args.lr,
                              betas=(0.9, 0.95), weight_decay=args.weight_decay)

    best_val = float("inf")
    t0 = time.time()
    for step in range(args.max_steps + 1):
        lr = lr_at(step, args.warmup, args.max_steps, args.lr, args.min_lr)
        for g in optim.param_groups:
            g["lr"] = lr

        if step % args.eval_interval == 0 or step == args.max_steps:
            losses = estimate_loss(model, splits, args.block_size,
                                   args.batch_size, device, args.eval_iters)
            dt = time.time() - t0
            print(f"step {step:5d} | train {losses['train']:.3f} | "
                  f"val {losses['val']:.3f} | lr {lr:.1e} | {dt:.0f}s")
            print("   sample:", sample(model, tok, device).replace("\n", " ⏎ ")[:160])
            if losses["val"] < best_val:
                best_val = losses["val"]
                torch.save({"model": model.state_dict(),
                            "config": asdict(cfg),
                            "step": step, "val_loss": best_val},
                           args.out)

        if step == args.max_steps:
            break

        x, y = get_batch(train_data, args.block_size, args.batch_size, device)
        _, loss = model(x, y)
        optim.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), args.grad_clip)
        optim.step()

    print(f"done. best val loss {best_val:.3f} -> {args.out}")


if __name__ == "__main__":
    main()
