# PromptMAXX portfolio case study

## One-line summary

PromptMAXX is a local-first macOS prompt-engineering workbench that turns rough
text into a typed, compilable prompt, compares controlled candidates, checks
observable output requirements, and preserves inspectable local evidence.

This is a portfolio case study of the implemented product foundation. It is
not a claim of a signed distribution artifact, hosted CI result, screenshot
set, or general model-quality benchmark.

## The problem

Prompt editing is often judged from one final string. That makes it difficult
to answer basic engineering questions: What changed? Which model/profile made
the change? Was the request valid? Did a later result arrive after the user
cancelled it? Can another person inspect the inputs and failures without
trusting a hidden score?

PromptMAXX treats those questions as product requirements. The target user is
someone who wants the speed of a local model but the discipline of a small,
reviewable engineering experiment.

## Product thesis

The product is organized around an evidence loop:

```text
rough source
  → typed PromptSpec
  → local validation
  → deterministic compilation
  → controlled comparison/evaluation
  → exact evidence and raw outputs/errors
  → trace, inspect, and export
```

The thesis is deliberately narrower than “AI knows which prompt is best.”
PromptMAXX records reproducible configuration and observable outcomes so a
person can make that judgment with context.

## What is implemented

- `PromptSpec`, profiles, and `PromptCompiler` provide versioned domain values,
  validation, deterministic rendering, and an editable spec review surface.
- `RefinementEngine` asks Ollama for the app-owned JSON contract, reassembles
  streamed chunks, allows one bounded corrective retry, and refuses to compile
  invalid output.
- Candidate comparison runs the same source through 2–4 explicit
  model/profile configurations and retains status, attempts, timing, tokens,
  output, and typed errors without fabricating a quality score.
- Evaluation Lab runs a small support-ticket fixture with structural checks and
  exact typed JSON scalar checks. It reports evidence-rich failures, raw model
  output, and configuration rather than an LLM judge.
- Versioned prompt-library and run-trace stores use validation, atomic writes,
  recovery behavior, hashes, filtering, and redacted/reveal export.
- Context Inspector imports text/Markdown, chunks and embeds it locally,
  retrieves with semantic, lexical, and MMR diversity signals, shows
  provenance, and copies an untrusted-data envelope. It does not generate an
  answer or invent citations.

## Architecture and data flow

SwiftUI feature views own user intent, visible state, cancellation, and error
feedback. Framework-light domain types own validation and Codable formats.
`ModelProvider` and `EmbeddingProvider` keep generation and embedding
orchestration independent from Ollama-specific HTTP details. `OllamaClient` is
actor-isolated and uses typed endpoint/status/decoding/cancellation behavior.

The main data paths are:

1. The editor sends source text and a selected profile to `RefinementEngine`.
2. The engine requests a typed JSON `PromptSpec`; local validation gates
   compilation.
3. `PromptComparisonRunner` and `EvaluationRunner` build explicit candidate
   requests, preserve ordered results, and cooperate with cancellation.
4. `RunTraceFactory` converts factual refinement, comparison, and evaluation
   outcomes into immutable traces. `TraceStore` serializes appends before the
   repository writes them atomically.
5. `GroundingStore` sends text batches through `EmbeddingProvider`, persists a
   validated endpoint-scoped local index, retrieves chunks, and compiles a
   JSON-encoded untrusted envelope for inspection or downstream use.

The storage and privacy boundary is documented in
[Privacy, storage, backup, and recovery](PRIVACY_AND_STORAGE.md). The default
Ollama endpoint is loopback. A custom non-loopback endpoint uses HTTP, so
prompt text, instructions, and model requests leave the Mac without
PromptMAXX terminating TLS.

## AI reliability and evaluation choices

Reliability comes from making model output a bounded input to local code:

- The generation request uses JSON format and `think=false`; source values are
  delimited as untrusted data so embedded instructions are not promoted to
  policy.
- JSON is decoded into typed values and validated before compilation. A
  malformed or incomplete response receives at most one corrective retry; a
  provider error, empty input, cancellation, or repeated invalid response is
  surfaced as a typed failure.
- Exact evaluation checks support nested paths and scalar string/number/bool/
  null equality. Missing paths, wrong types, and mismatched values are
  separate evidence states.
- Comparison and evaluation preserve candidate identity, options, timestamps,
  errors, partial output, and cancellation status. They do not infer human
  preference, factual truth outside the fixture, or a universal winner.

Grounding is intentionally a retrieval foundation rather than an answer
generator. The embedding model and vector dimension are part of index
identity. Ranking exposes semantic relevance, lexical contribution, and
diversity/MMR contribution—not confidence. Retrieved content is JSON-encoded
inside a marked untrusted envelope with source/chunk provenance, which keeps
delimiter-like text data rather than executable instruction.

## Failure modes designed into the product

| Failure | Observable behavior |
| --- | --- |
| Ollama unavailable or wrong endpoint | Setup validation and typed transport/HTTP error; no guessed output |
| Malformed or incomplete PromptSpec JSON | Bounded corrective retry, then validation error; no invalid compilation |
| User cancellation or superseded run | Cooperative cancellation and run-token gates prevent late UI/traces; already committed cases remain |
| Model warm-up or slow local hardware | Factual latency/token metadata; no quality conclusion from timing |
| Corrupt/unsupported local store | Preserve the primary bytes and require explicit recovery/discard behavior |
| Embedding model/dimension mismatch | Reject incompatible index entries rather than mixing vector spaces |
| Prompt/content injection in grounding data | Treat retrieved content as serialized untrusted data with provenance |
| PDF or answer-citation request | Explicitly out of scope; text/Markdown only, no fabricated extraction or citations |

## Evidence rules

Evidence is useful only when its origin and limits are clear. The portfolio
record should therefore include:

- the exact candidate/profile/model/options and suite version;
- source/spec/compiled text where an unredacted view is authorized;
- raw provider output, typed errors, cancellation/status, and known timing or
  token metadata;
- exact check IDs, expected/actual scalar values, and failure details;
- retrieval scores and provenance, labeled as ranking signals; and
- the export date, local environment, and any model/version information that
  was actually measured.

Never fill a result with a plausible metric. Use placeholders such as
`[MEASURED PASS RATE]`, `[MEASURED RECALL@K]`, or `[MEASURED LATENCY]` until a
repeatable run has produced the number. A small fixture is evidence of the
fixture’s contract, not proof of general prompt quality.

The repository now includes one concrete retrieval measurement in
[samples/grounding-benchmark/](../samples/grounding-benchmark/). On 2026-08-18,
a Mac mini Apple M4 Pro running macOS 26.5.2, Ollama 0.24.0, and
`bge-m3:latest` (digest
`7907646426070047a77226ac3e684fbbe8410524f7b4a74d02837e43f2146bab`) produced
the following with 1024-dimensional embeddings and chunk 800/overlap 120,
lexical weight 0.15, MMR lambda 0.75, same-source penalty 0.1, top-k 3, and
character budget 2000:

| Split | Hit rate @ 3 | Mean recall @ 3 | Source coverage | Errors / zero results |
| --- | ---: | ---: | ---: | ---: |
| Tuning ([JSON](../samples/grounding-benchmark/grounding-bge-m3-latest-tuning-20260818T031703Z.json), [Markdown](../samples/grounding-benchmark/grounding-bge-m3-latest-tuning-20260818T031703Z.md)) | 100% (10/10) | 100% | 100% | 0 / 0 |
| Held-out ([JSON](../samples/grounding-benchmark/grounding-bge-m3-latest-held-out-20260818T031611Z.json), [Markdown](../samples/grounding-benchmark/grounding-bge-m3-latest-held-out-20260818T031611Z.md)) | 100% (10/10) | 95% | 100% | 0 / 0 |

The held-out report records `q-heldout-10` retrieving one of two relevant
sources (50% case recall). The fixed defaults were not changed after the
held-out run. This remains one run over a small original fixture and measures
retrieval only; it is not statistical confidence, answer-quality evidence, or
a confidence score.

## What I can explain in an interview

I can walk through the domain boundaries, why `PromptSpec` is safer than
editing an opaque string, how actor isolation and injected providers make
local networking testable, and how run tokens prevent stale async results from
being persisted. I can explain why the evaluator uses exact scalar checks
instead of an LLM judge, why retrieval scores are not confidence, and why
grounding data is serialized as untrusted content. I can also show the
trade-offs: a local Ollama dependency, warm-up-sensitive latency, small
fixture coverage, HTTP privacy caveats for custom endpoints, and the absence
of PDF extraction or answer generation.

For a portfolio presentation, I would replace only these measured placeholders
with recorded evidence:

```text
Fixture: support-ticket-json-v1
Generation model/tag: [MEASURED MODEL TAG]
Original pass rate: [MEASURED ORIGINAL PASS RATE]
Refined pass rate: [MEASURED REFINED PASS RATE]
Mean latency: [MEASURED LATENCY]
Grounding recall@k / source coverage: [MEASURED RETRIEVAL RESULTS]
Environment: [MACOS / XCODE / OLLAMA / MODEL DETAILS]
```

The current repository still treats signing/notarization, hosted CI evidence,
and screenshot capture as release/presentation work rather than completed
artifacts.
