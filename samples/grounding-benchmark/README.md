# PromptMAXX grounding benchmark evidence

These checked-in reports measure retrieval only against the small original
`promptmaxx-grounding-demo` corpus and its versioned tuning/held-out query
splits. They do not measure answer quality, citation correctness, model
confidence, or general RAG quality. This is one local run, not statistical
confidence.

## Checked-in reports

- [Tuning JSON](grounding-bge-m3-latest-tuning-20260818T031703Z.json) ·
  [Tuning Markdown](grounding-bge-m3-latest-tuning-20260818T031703Z.md)
- [Held-out JSON](grounding-bge-m3-latest-held-out-20260818T031611Z.json) ·
  [Held-out Markdown](grounding-bge-m3-latest-held-out-20260818T031611Z.md)

## Measurement record

- Date: 2026-08-18
- Machine: Mac mini, Apple M4 Pro
- OS: macOS 26.5.2
- Ollama: 0.24.0
- Embedding model: `bge-m3:latest`
- Provider/model digest:
  `7907646426070047a77226ac3e684fbbe8410524f7b4a74d02837e43f2146bab`
- Embedding dimensions: 1024
- Endpoint: local loopback; the benchmark sends no fixture to a remote host

Fixed configuration in both reports:

```text
chunk size / overlap: 800 / 120
lexical weight:       0.15
MMR lambda:            0.75
same-source penalty:   0.10
top-k:                 3
character budget:      2000
```

## Results

| Split | Cases | Hit rate @ 3 | Mean recall @ 3 | Source coverage | Errors / zero results |
| --- | ---: | ---: | ---: | ---: | ---: |
| Tuning | 10/10 | 100% | 100% | 100% | 0 / 0 |
| Held-out | 10/10 | 100% | 95% | 100% | 0 / 0 |

The held-out report contains one useful limitation: `q-heldout-10` retrieves
one of two relevant sources, so its case recall is 50% even though the query
is a hit and the aggregate union source coverage remains 100%.

The fixed defaults were not changed after inspecting the held-out result.
Broader parameter sweeps, repeated runs, larger corpora, and statistical
confidence intervals remain follow-up work.

## Integrity checks

The checked-in report hashes are:

| File | SHA-256 |
| --- | --- |
| `grounding-bge-m3-latest-tuning-20260818T031703Z.json` | `2f96ce62fba4dd53e503c27b57528cdb4ad37a38074ed154d25c274999059e70` |
| `grounding-bge-m3-latest-tuning-20260818T031703Z.md` | `cc0268f7d39ec31dd225d6f6c0d0551cad4ce158db3e1b5aeb84a46c8c88458b` |
| `grounding-bge-m3-latest-held-out-20260818T031611Z.json` | `893bff5764d9fb77a7ba8a1fef1f4804f5b9610e3c4303351b60231284a000e9` |
| `grounding-bge-m3-latest-held-out-20260818T031611Z.md` | `ce058009810aa5312be75408cdaecae9415fe591af40304b5302ade87968e4ce` |

From the repository root, verify all four with:

```bash
shasum -a 256 -c <<'EOF'
2f96ce62fba4dd53e503c27b57528cdb4ad37a38074ed154d25c274999059e70  samples/grounding-benchmark/grounding-bge-m3-latest-tuning-20260818T031703Z.json
cc0268f7d39ec31dd225d6f6c0d0551cad4ce158db3e1b5aeb84a46c8c88458b  samples/grounding-benchmark/grounding-bge-m3-latest-tuning-20260818T031703Z.md
893bff5764d9fb77a7ba8a1fef1f4804f5b9610e3c4303351b60231284a000e9  samples/grounding-benchmark/grounding-bge-m3-latest-held-out-20260818T031611Z.json
ce058009810aa5312be75408cdaecae9415fe591af40304b5302ade87968e4ce  samples/grounding-benchmark/grounding-bge-m3-latest-held-out-20260818T031611Z.md
EOF
```

## Reproduce locally

The public fixture and benchmark CLI are wired through
[`scripts/run-grounding-benchmark.sh`](../../scripts/run-grounding-benchmark.sh).
It requires a local Ollama server with `bge-m3:latest` installed. New runs
publish an atomic bundle at `<output-dir>/<stem>/` containing `report.json` and
`report.md`; the CLI refuses to overwrite an existing bundle. The checked-in
evidence above predates that layout and intentionally remains as flat,
timestamped JSON/Markdown files:

```bash
ollama serve
ollama pull bge-m3:latest

scripts/run-grounding-benchmark.sh \
  --model bge-m3:latest --dimensions 1024 --split tuning \
  --chunk-size 800 --overlap 120 --lexical-weight 0.15 \
  --mmr-lambda 0.75 --source-penalty 0.1 --top-k 3 \
  --character-budget 2000 --output-dir benchmark-results

scripts/run-grounding-benchmark.sh \
  --model bge-m3:latest --dimensions 1024 --split held-out \
  --chunk-size 800 --overlap 120 --lexical-weight 0.15 \
  --mmr-lambda 0.75 --source-penalty 0.1 --top-k 3 \
  --character-budget 2000 --output-dir benchmark-results
```

For repository verification, [`scripts/verify.sh`](../../scripts/verify.sh)
performs the unsigned test/build/analyze workflow. The benchmark itself is
not a live requirement for the unit-test suite.

See the [portfolio case study](../../docs/CASE_STUDY.md),
[interview talk track](../../docs/INTERVIEW_TALK_TRACK.md), and
[capture-ready demo](../../docs/DEMO_SCRIPT.md) for the engineering context.
