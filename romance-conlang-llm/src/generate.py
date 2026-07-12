"""
generate.py — sample Solira text from the trained model (PyTorch).

Auto-selects Apple-silicon MPS when available, else CPU.

    python src/generate.py                         # a few random sentences
    python src/generate.py --genre HISTORIA -n 200 # steer by genre
    python src/generate.py --prompt "[FRASE] Le gato"
    python src/generate.py --chat                  # interactive REPL
"""
import argparse
import os

import torch

from model import GPT, GPTConfig
from tokenizer import BPETokenizer

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
GENRES = ["FRASE", "DIALOG", "HISTORIA", "SALU", "QA"]


def pick_device(requested):
    if requested and requested != "auto":
        return requested
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def load(ckpt_path, tok_path, device):
    tok = BPETokenizer.load(tok_path)
    ckpt = torch.load(ckpt_path, map_location=device)
    cfg = GPTConfig(**ckpt["config"])
    model = GPT(cfg).to(device)
    model.load_state_dict(ckpt["model"])
    model.eval()
    return model, tok, ckpt


def pretty(text):
    """Put each genre-tagged document / dialogue turn on its own line."""
    for tag in ("[FRASE]", "[QA]", "[DIALOG]", "[HISTORIA]", "[SALU]"):
        text = text.replace(tag, "\n" + tag)
    return text.replace(" — ", "\n  — ").strip()


@torch.no_grad()
def run(model, tok, device, prompt, n, temperature, top_k):
    ids = tok.encode(prompt)
    x = torch.tensor([ids], dtype=torch.long, device=device)
    out = model.generate(x, n, temperature=temperature, top_k=top_k)[0].tolist()
    return tok.decode(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", default=None, help="raw text to continue")
    ap.add_argument("--genre", default=None, choices=GENRES,
                    help="seed with a genre tag")
    ap.add_argument("-n", "--num-tokens", type=int, default=120)
    ap.add_argument("--num-samples", type=int, default=4)
    ap.add_argument("--temperature", type=float, default=0.9)
    ap.add_argument("--top-k", type=int, default=40)
    ap.add_argument("--device", default="auto")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--ckpt", default=os.path.join(DATA, "model.pt"))
    ap.add_argument("--tokenizer", default=os.path.join(DATA, "tokenizer.json"))
    ap.add_argument("--chat", action="store_true", help="interactive REPL")
    args = ap.parse_args()

    if args.seed is not None:
        torch.manual_seed(args.seed)
    device = pick_device(args.device)
    model, tok, ckpt = load(args.ckpt, args.tokenizer, device)
    print(f"# device={device}  params={model.num_params():,}  "
          f"trained_step={ckpt.get('step')}  val_loss={ckpt.get('val_loss'):.3f}\n")

    if args.chat:
        print("Type a Solira prefix (or a genre like HISTORIA). Ctrl-D to quit.\n")
        while True:
            try:
                line = input("solira> ").strip()
            except EOFError:
                print()
                break
            if not line:
                continue
            if line.upper() in GENRES:
                line = f"[{line.upper()}] "
            print(pretty(run(model, tok, device, line, args.num_tokens,
                             args.temperature, args.top_k)), "\n")
        return

    if args.prompt is not None:
        prompt = args.prompt
    elif args.genre is not None:
        prompt = f"[{args.genre}] "
    else:
        prompt = "[FRASE] "

    for _ in range(args.num_samples):
        print(pretty(run(model, tok, device, prompt, args.num_tokens,
                         args.temperature, args.top_k)))
        print("-" * 60)


if __name__ == "__main__":
    main()
