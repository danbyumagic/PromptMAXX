# Solira — a ~1M-parameter LLM that speaks a new Romance conlang

A tiny language model (**~1.1M parameters**) trained from scratch to generate
**Solira**, a constructed Romance language blended from **Spanish, French, and
English**. Everything is self-contained and designed to train in minutes and
run instantly on an **Apple-silicon Mac mini** (or any Mac / Linux box).

- The language itself is documented in **[LANGUAGE.md](LANGUAGE.md)** — a real
  grammar with regular morphology, two copulas, periphrastic tenses, and a
  ~300-word dictionary.
- The model is a small decoder-only Transformer (GPT-style) with a custom
  512-token BPE tokenizer.
- Inference runs on **PyTorch/MPS** _or_ with **numpy alone** (no PyTorch
  needed) — the checkpoint is only a few megabytes.

> Solira is generated text: the model learns Solira's morphology and syntax,
> not facts about the world, so sentences are grammatical and fluent but often
> whimsical ("the black cat watches the long sea"). That's expected for a 1M
> model trained on a synthetic corpus.

---

## Quickstart on a Mac mini (Apple silicon)

```bash
cd romance-conlang-llm
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Reproduce the whole pipeline (corpus → tokenizer → train → export → sample).
# Training uses the MPS (Apple GPU) backend automatically when available.
make all
```

That's it. To just talk to the model interactively:

```bash
python src/generate.py --chat
```

```
solira> HISTORIA
[HISTORIA] Le enfant era joven e felis. La madre bela kantava en le jardin ...

solira> [FRASE] Le gato
[FRASE] Le gato negro dormi sur la tabla vela ...
```

### Don't want to install PyTorch?

The model is small enough to run in pure numpy:

```bash
pip install numpy                 # the only dependency
python src/generate_numpy.py --genre HISTORIA -n 200
```

---

## What's in here

| File | Purpose |
|---|---|
| `LANGUAGE.md` | The Solira language spec + dictionary |
| `src/lexicon.py` | The dictionary as data (nouns, verbs, adjectives, …) |
| `src/morphology.py` | The inflection engine (conjugation, agreement) |
| `src/grammar.py` | Grammar that composes sentences, dialogues, stories |
| `src/generate_corpus.py` | Writes the training corpus (`data/corpus.txt`) |
| `src/tokenizer.py` | Self-contained BPE tokenizer (train / encode / decode) |
| `src/model.py` | The ~1.1M-param GPT (`GPTConfig`, `GPT`) |
| `src/train.py` | Training loop (MPS / CPU / CUDA auto-select) |
| `src/generate.py` | Sampling + interactive REPL (PyTorch) |
| `src/export_numpy.py` | Export weights to a portable `.npz` |
| `src/generate_numpy.py` | numpy-only inference (no PyTorch) |

Each module runs standalone (`python src/<file>.py`) and prints a self-check.

---

## Steering generation

The corpus is tagged by genre, so you can steer the model with a prompt token:

```bash
python src/generate.py --genre FRASE      # a single sentence
python src/generate.py --genre DIALOG     # a spoken exchange
python src/generate.py --genre HISTORIA   # a short story
python src/generate.py --genre SALU       # a greeting
python src/generate.py --genre QA         # a question + answer
python src/generate.py --prompt "[FRASE] La reina"   # free continuation
```

Sampling knobs: `--temperature` (default 0.9), `--top-k` (default 40),
`-n` tokens, `--num-samples`, `--seed`.

---

## Model card

<!-- METRICS -->

- **Architecture:** decoder-only Transformer — 5 layers, 4 heads, d_model 128,
  block size 256, tied embeddings, GELU MLP (4×). **1,089,920 parameters.**
- **Tokenizer:** custom character-level BPE, **512** tokens, ~2.6 chars/token.
- **Training data:** 50,000 procedurally-generated Solira documents
  (~3.9M characters / ~1.2M tokens), across 5 genres.
- **Training:** AdamW, warmup + cosine LR, ~3000 steps on CPU (minutes on MPS).
- **Backends:** PyTorch (CPU / MPS / CUDA) and a dependency-free numpy path.

## Retraining / customizing

```bash
# bigger corpus, longer training, explicit device
python src/generate_corpus.py --docs 100000
python src/tokenizer.py --vocab-size 512
python src/train.py --max-steps 6000 --device mps

# resize the model (still tiny)
python src/train.py --n-layer 6 --n-embd 160
```

Want to change the language? Edit `src/lexicon.py` / `src/grammar.py`,
regenerate the corpus, retrain. The whole loop is deterministic given a seed.
