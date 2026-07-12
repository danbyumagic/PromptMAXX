"""
tokenizer.py — a small, self-contained byte-pair-encoding tokenizer.

No external dependencies. Trains merges over the Solira corpus and encodes to
a compact vocabulary (~512 tokens by default), which keeps the model's
embedding table small so the parameter budget goes into the transformer.

Design notes:
  * Genre tags ([FRASE], [DIALOG], ...) are atomic *special* tokens: they are
    never split, so the model can be steered with a single prompt token.
  * A leading space is encoded with the marker "▁" (SentencePiece style),
    so decode() reconstructs the original text exactly (round-trip safe).
  * BPE is trained on whitespace-delimited chunks (fast) and never merges
    across chunk boundaries.
"""
import json
import re
from collections import Counter

SPACE = "▁"          # ▁ marks "a space preceded this token"
PAD, UNK = "<pad>", "<unk>"
GENRE_TAGS = ["[FRASE]", "[DIALOG]", "[HISTORIA]", "[SALU]", "[QA]"]
DEFAULT_SPECIALS = [PAD, UNK] + GENRE_TAGS

# split a special-free span into chunks: each newline is its own token; every
# other chunk is an optional leading marker plus a run of non-marker chars.
_CHUNK_RE = re.compile(r"\n|" + SPACE + r"?[^" + SPACE + r"\n]+")


def _pretokenize(span: str):
    """Turn a plain text span into BPE chunks (spaces -> leading ▁)."""
    return _CHUNK_RE.findall(span.replace(" ", SPACE))


class BPETokenizer:
    def __init__(self):
        self.tokens = []                 # id -> token string
        self.token_to_id = {}            # token string -> id
        self.merges = []                 # ordered list of (a, b) string pairs
        self.ranks = {}                  # (a, b) -> merge order
        self.specials = []
        self._special_re = None
        self._cache = {}                 # chunk string -> list[int]

    # -- properties ----------------------------------------------------------
    @property
    def vocab_size(self):
        return len(self.tokens)

    @property
    def unk_id(self):
        return self.token_to_id[UNK]

    @property
    def pad_id(self):
        return self.token_to_id[PAD]

    def _rebuild(self):
        self.token_to_id = {t: i for i, t in enumerate(self.tokens)}
        self.ranks = {tuple(p): i for i, p in enumerate(self.merges)}
        self._cache = {}
        # match the longest special first
        esc = sorted((re.escape(s) for s in self.specials), key=len, reverse=True)
        self._special_re = re.compile("(" + "|".join(esc) + ")") if esc else None

    # -- training ------------------------------------------------------------
    def train(self, text, vocab_size=512, specials=None, verbose=False):
        self.specials = list(specials or DEFAULT_SPECIALS)
        # strip specials out before gathering character statistics
        spans = re.split("(" + "|".join(re.escape(s) for s in self.specials) + ")", text)
        chunk_freq = Counter()
        for span in spans:
            if span in self.specials or span == "":
                continue
            chunk_freq.update(_pretokenize(span))

        # each chunk is a tuple of symbols; start from single characters
        words = {tuple(chunk): freq for chunk, freq in chunk_freq.items()}
        base = sorted({ch for w in words for ch in w})
        self.tokens = list(self.specials) + base
        self.merges = []

        while len(self.tokens) < vocab_size:
            pairs = Counter()
            for w, freq in words.items():
                for i in range(len(w) - 1):
                    pairs[(w[i], w[i + 1])] += freq
            if not pairs:
                break
            best = max(pairs, key=pairs.get)
            if pairs[best] < 2:
                break
            self.merges.append(best)
            self.tokens.append(best[0] + best[1])
            words = {self._merge_word(w, best): freq for w, freq in words.items()}
            if verbose and len(self.tokens) % 50 == 0:
                print(f"  vocab {len(self.tokens)}  last merge {best!r} x{pairs[best]}")

        self._rebuild()
        return self

    @staticmethod
    def _merge_word(word, pair):
        merged = pair[0] + pair[1]
        out, i, n = [], 0, len(word)
        while i < n:
            if i < n - 1 and word[i] == pair[0] and word[i + 1] == pair[1]:
                out.append(merged)
                i += 2
            else:
                out.append(word[i])
                i += 1
        return tuple(out)

    # -- encoding ------------------------------------------------------------
    def _bpe(self, chunk):
        symbols = list(chunk)
        while len(symbols) >= 2:
            best_rank, best_i = None, -1
            for i in range(len(symbols) - 1):
                r = self.ranks.get((symbols[i], symbols[i + 1]))
                if r is not None and (best_rank is None or r < best_rank):
                    best_rank, best_i = r, i
            if best_i < 0:
                break
            symbols[best_i:best_i + 2] = [symbols[best_i] + symbols[best_i + 1]]
        return [self.token_to_id.get(s, self.unk_id) for s in symbols]

    def encode(self, text):
        ids = []
        if self._special_re is None:
            self._rebuild()
        for piece in self._special_re.split(text):
            if piece == "":
                continue
            if piece in self.token_to_id and piece in self.specials:
                ids.append(self.token_to_id[piece])
                continue
            for chunk in _pretokenize(piece):
                cached = self._cache.get(chunk)
                if cached is None:
                    cached = self._bpe(chunk)
                    self._cache[chunk] = cached
                ids.extend(cached)
        return ids

    def decode(self, ids):
        out = []
        for i in ids:
            if 0 <= i < len(self.tokens):
                out.append(self.tokens[i])
        return "".join(out).replace(SPACE, " ")

    # -- persistence ---------------------------------------------------------
    def save(self, path):
        with open(path, "w", encoding="utf-8") as f:
            json.dump({
                "specials": self.specials,
                "tokens": self.tokens,
                "merges": self.merges,
            }, f, ensure_ascii=False)

    @classmethod
    def load(cls, path):
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        t = cls()
        t.specials = d["specials"]
        t.tokens = d["tokens"]
        t.merges = [tuple(m) for m in d["merges"]]
        t._rebuild()
        return t


def _train_cli():
    import argparse
    import os
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--vocab-size", type=int, default=512)
    args = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    data = os.path.join(os.path.dirname(here), "data")
    corpus = args.corpus or os.path.join(data, "corpus.txt")
    out = args.out or os.path.join(data, "tokenizer.json")

    text = open(corpus, encoding="utf-8").read()
    tok = BPETokenizer().train(text, vocab_size=args.vocab_size, verbose=True)
    tok.save(out)
    print(f"trained vocab={tok.vocab_size}  saved -> {out}")

    # round-trip check on a few lines
    ok = True
    for line in text.splitlines()[:2000]:
        if tok.decode(tok.encode(line)) != line:
            ok = False
            print("MISMATCH:", repr(line))
            print("     got:", repr(tok.decode(tok.encode(line))))
            break
    print("round-trip on 2000 lines:", "OK" if ok else "FAILED")
    ids = tok.encode(text[:400])
    print(f"compression: {len(text[:400])} chars -> {len(ids)} tokens "
          f"({len(text[:400])/max(1,len(ids)):.2f} chars/token)")


if __name__ == "__main__":
    _train_cli()
