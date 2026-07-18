"""
generate_corpus.py — materialise a Solira training corpus.

Writes one genre-tagged document per line to data/corpus.txt (plus a small
held-out data/val.txt), and prints corpus statistics. Deterministic given
--seed so runs are reproducible.

    python src/generate_corpus.py --docs 50000
"""
import argparse
import os
from collections import Counter

from grammar import Gen, GENRE_TAGS

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")


def build(n_docs, seed):
    g = Gen(seed)
    docs, genres = [], Counter()
    seen = set()
    # Generate a bit extra so near-duplicates can be dropped without going short.
    attempts = 0
    while len(docs) < n_docs and attempts < n_docs * 3:
        attempts += 1
        d = g.document()
        # de-duplicate exact repeats (short [FRASE]/[SALU] docs collide often)
        if d in seen:
            continue
        seen.add(d)
        docs.append(d)
        genres[d.split(" ", 1)[0]] += 1
    return docs, genres


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--docs", type=int, default=50000,
                    help="number of training documents")
    ap.add_argument("--val-docs", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=1234)
    ap.add_argument("--out", default=DATA)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)

    train, genres = build(args.docs, args.seed)
    val, _ = build(args.val_docs, args.seed + 99991)
    # keep val disjoint from train
    train_set = set(train)
    val = [d for d in val if d not in train_set][: args.val_docs]

    train_path = os.path.join(args.out, "corpus.txt")
    val_path = os.path.join(args.out, "val.txt")
    with open(train_path, "w", encoding="utf-8") as f:
        f.write("\n".join(train) + "\n")
    with open(val_path, "w", encoding="utf-8") as f:
        f.write("\n".join(val) + "\n")

    text = "\n".join(train)
    chars = Counter(text)
    words = Counter(text.replace("\n", " ").split())
    print(f"wrote {len(train)} train docs -> {train_path}")
    print(f"wrote {len(val)} val docs   -> {val_path}")
    print(f"chars: {len(text):,}  |  unique chars: {len(chars)}")
    print(f"unique word types: {len(words):,}  |  total word tokens: {sum(words.values()):,}")
    print("genre distribution:", dict(genres))
    print("alphabet:", "".join(sorted(c for c in chars if not c.isspace())))
    print("\n--- sample ---")
    for d in train[:6]:
        print(d)


if __name__ == "__main__":
    main()
