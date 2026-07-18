# INFO — Solira tiny-LLM (quick reference)

**What:** a ~1.1M-parameter GPT trained from scratch to speak **Solira**, a new
Romance conlang blended from **Spanish + French + English**. Runs locally on an
Apple-silicon Mac (MPS) or plain CPU — and with **numpy alone**, no PyTorch.

## Facts

| | |
|---|---|
| Parameters | **1,089,920** (5 layers, 4 heads, d=128, block 256) |
| Tokenizer | custom BPE, 512 tokens (~2.6 chars/token) |
| Corpus | 50k generated docs · ~3.9M chars · 5 genres |
| Final val loss | **1.537** (≈ perplexity 4.65) — converged for this size |
| Backends | PyTorch (CPU/MPS/CUDA) · numpy-only (matches torch to 4e-6) |
| Runs out of the box? | Yes — trained weights are committed |

## Run it

```bash
cd romance-conlang-llm
pip install -r requirements.txt

python src/generate.py --chat              # PyTorch / Apple MPS
python src/generate_numpy.py --genre HISTORIA   # numpy only, no torch
make all                                   # reproduce corpus→tokenizer→train→sample
```

Steer with a genre: `FRASE` (sentence), `DIALOG`, `HISTORIA` (story),
`SALU` (greeting), `QA`.

## Sample

> *[HISTORIA] Un jorno, le mestre sali de su kasa. La fema viela a tornat sur un mercato. E eli viven felis por sempre.*
> — One day, the teacher left his house. The old woman returned to a market. And they live happy forever.

## Where to look

| File | What |
|---|---|
| `README.md` | Full guide, model card, retraining |
| `LANGUAGE.md` | The Solira grammar + ~300-word dictionary |
| `src/` | Pipeline: morphology → grammar → corpus → tokenizer → model → train → generate |
| `data/model.pt` | The trained checkpoint |

_Note: generated text is grammatically fluent but semantically playful — the
model learns Solira's morphology and syntax, not facts about the world._
