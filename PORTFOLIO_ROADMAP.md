# PromptMAXX Portfolio Roadmap

PromptMAXX is being developed as a local-first prompt-engineering workbench.
The portfolio story is an evidence loop: structured generation, local
validation, deterministic compilation, controlled candidate runs, mechanical
evaluation, and reviewable exports.

## Current status

| Area | Status | Evidence in this repository |
| --- | --- | --- |
| Ollama foundation | Implemented | Typed endpoint validation, injected `URLSession`, actor client, streaming DTOs, HTTP/error handling, timeouts, cancellation, and endpoint tests |
| PromptSpec workflow | Implemented | Versioned profiles/specs, schema validation, deterministic `PromptCompiler`, corrective retry, spec editor, run details |
| Candidate comparison | Implemented | 2–4 unique model/profile candidates, stable ordering, bounded concurrency, sequential UI default, factual metrics, no score |
| Evaluation Lab | Implemented | Eight support-ticket cases, same-model controlled candidates, structural plus exact typed JSON-scalar checks, evidence cards, JSON/Markdown export |
| Prompt library | Implemented | Versioned Codable documents, atomic writes, backup/recovery, validation, import/export, migration, and library UI |
| Run traces | Implemented | Versioned traces, hashes, validation, serialized persistence, filtering, retention, redacted/reveal export, and Trace Browser |
| Grounded context | Implemented text/Markdown foundation and inspector | `/api/embed`, model/dimension identity, deterministic chunks, hybrid semantic+lexical+MMR ranking, provenance, untrusted envelope, and local index persistence |
| Retrieval benchmark | Measured baseline | Versioned original corpus, tuning/held-out splits, deterministic metrics, checked-in JSON/Markdown evidence, and reproducible CLI |
| Release distribution | Packaging in progress | Local verification and release documentation exist; hosted CI evidence, signing, and notarization are not completed |

The 2026-08-18 local portfolio snapshot passed all 164 tests, both unsigned
Debug and universal Release builds, and static analysis with Xcode 26.5 on
macOS 26.5.2. No broad model-quality claim, hosted CI result, signed artifact,
or public release URL is implied.

## Product thesis and evidence loop

1. A rough request becomes a typed `PromptSpec` rather than an opaque text
   blob.
2. Local validation rejects incomplete or unsupported structure before compile.
3. `PromptCompiler` produces stable output from the same spec.
4. Comparison runs preserve candidate identity, status, cancellation, timing,
   token metadata, and output without fabricating a quality score.
5. Evaluation runs observable checks against a versioned fixture suite and
   exports the complete evidence.

This demonstrates typed domain modeling, defensive provider integration, Swift
concurrency, controlled experiments, and local-first product boundaries. It
does not claim that structural checks replace human judgment.

## Execution plan and acceptance gates

Each phase ends with reviewable evidence rather than a subjective “the AI seems
better” claim. Completed phases remain here so an interviewer can see how the
system was decomposed and verified.

### P0 — Reliable AI client and test foundation (completed)

**Goal:** make every later AI feature depend on a defensible transport layer.

- Replace stringly typed host/port handling with a validated `OllamaEndpoint`.
- Isolate transport behind injected provider protocols and an actor client.
- Treat non-2xx responses, malformed NDJSON, streamed provider errors, missing
  terminal chunks, oversized lines, timeouts, and cancellation as typed errors.
- Add deterministic provider/URL-session fixtures, a shared Xcode scheme, CI,
  an MIT license, and unsigned Debug/Release verification.

**Acceptance evidence:** invalid endpoints cannot form requests; truncated
streams cannot produce successful output; tests use no live model or personal
data; both unsigned build configurations pass.

**Portfolio signal:** defensive API integration, Swift concurrency, dependency
injection, and ordinary software-engineering rigor around an AI feature.

### P1 — Typed PromptSpec compiler (completed)

**Goal:** turn opaque prompt rewriting into an inspectable, type-safe pipeline.

- Generate a versioned `PromptSpec` containing objective, context, constraints,
  assumptions, missing questions, output contract, acceptance criteria, and
  selected techniques.
- Validate structured model output locally; retry once with concise validation
  feedback; surface a real failure instead of silently accepting malformed data.
- Compile the validated spec deterministically in Swift and let the user edit
  it before accepting the result.
- Provide explicit prompt profiles and concise technique rationale without
  requesting or displaying hidden chain-of-thought.

**Acceptance evidence:** the same validated spec compiles identically; invalid
specs have typed field-level failures; mocked malformed/recovery cases are
covered; the editor exposes the spec and run details.

**Portfolio signal:** structured LLM output, schema contracts, recovery,
human-in-the-loop design, and deterministic post-processing.

### P2 — Controlled comparison and Evaluation Lab (completed)

**Goal:** demonstrate whether observable requirements improved under controlled
conditions instead of assigning an invented quality score.

- Run 2–4 unique model/profile candidates with stable identity, bounded
  concurrency, cancellation, and sequential execution as the local-safe default.
- Execute original and refined prompts against the same eight-case support
  fixture and visible deterministic generation settings.
- Score only executable facts: JSON validity, structure, required fields, and
  exact typed scalar values, with missing-versus-mismatch evidence.
- Export complete JSON and Markdown reports containing configuration, outputs,
  errors, latency, and token metadata.

**Acceptance evidence:** a reviewer can reproduce the candidate configuration,
inspect every failed check, and confirm that no single run is presented as a
universal benchmark or human preference result.

**Portfolio signal:** eval design, controlled experimentation, model
orchestration, factual metrics, and explicit measurement limitations.

### P3 — Durable library and LLM observability (completed)

**Goal:** make AI work reproducible after a window or app restart.

- Store versioned prompt documents with revisions, favorites, search,
  atomic writes, backup/recovery, migration, and validated import/export.
- Trace refinement, comparison, and evaluation stages with endpoint locality,
  model/profile versions, options, status, retries, timings, token metadata,
  hashes, failures, and cancellation.
- Serialize concurrent persistence, ignore superseded runs, and provide trace
  filtering, retention, redacted/reveal export, and a Trace Browser.

**Acceptance evidence:** corrupt or stale data produces an explicit recovery
path; concurrent terminal traces are not lost; cancelled/superseded UI work is
rejected before the serialized persistence boundary and cannot overwrite the
active document. Completed evidence that has entered that boundary remains
durable even if its originating UI is subsequently dismissed.

**Portfolio signal:** LLM observability, reproducibility, local privacy,
concurrency correctness, and failure-oriented product design.

### P4 — Inspectable local grounding foundation (completed)

**Goal:** add a transparent retrieval layer without overstating it as a complete
answer-citation system.

- Import bounded UTF-8 text/Markdown sources, chunk them deterministically, and
  embed through Ollama `/api/embed`.
- Version the embedding model/dimension index and scope its path to the endpoint.
- Rank with semantic similarity, lexical overlap, and MMR diversity; expose the
  selected chunks, scores, provenance, token budget, and pin/remove controls.
- Delimit retrieved text as untrusted data and preserve source IDs in the copied
  context envelope.

**Acceptance evidence:** corrupt/mismatched indexes fail explicitly; retrieval
fixtures cover ranking and numerical stability; the UI never labels similarity
as confidence or claims answer citations that do not exist.

**Portfolio signal:** embeddings, chunking, hybrid retrieval, provenance,
context-budget management, and prompt-injection awareness.

### P5 — Retrieval evaluation and demo corpus (measured baseline completed)

**Goal:** replace a feature-level RAG claim with measured retrieval evidence.

- A small original, redistributable corpus and versioned 10-query tuning and
  10-query held-out splits are checked in under
  [`samples/grounding-benchmark/`](samples/grounding-benchmark/).
- The deterministic evaluator reports hit rate, mean recall@k, union source
  coverage, and zero-result/error cases while preserving model digest,
  dimensions, chunk settings, ranking settings, and timestamps.
- Pretty JSON/Markdown reports are checked in for the local tuning run at
  `20260818T031703Z` and held-out run at `20260818T031611Z`.
- On 2026-08-18, a Mac mini Apple M4 Pro with macOS 26.5.2, Ollama 0.24.0,
  `bge-m3:latest` (digest
  `7907646426070047a77226ac3e684fbbe8410524f7b4a74d02837e43f2146bab`), and
  1024-dimensional embeddings produced 10/10 hits, 100% mean recall, and 100%
  source coverage on tuning; held-out produced 10/10 hits, 95% mean recall,
  and 100% source coverage. Both had zero errors and zero-result cases.
- The fixed defaults were not changed after the held-out result. The
  `q-heldout-10` case still shows the limitation: one of two relevant sources
  was retrieved (50% case recall).

This is one local retrieval-only run on a small original fixture, not
statistical confidence or an answer-quality claim. Broader parameter sweeps,
repeated runs, larger corpora, and confidence intervals remain follow-up work.

**Acceptance evidence:** a reviewer can inspect the exact
[tuning](samples/grounding-benchmark/grounding-bge-m3-latest-tuning-20260818T031703Z.md)
and
[held-out](samples/grounding-benchmark/grounding-bge-m3-latest-held-out-20260818T031611Z.md)
reports and reproduce the evaluator with
[`scripts/run-grounding-benchmark.sh`](scripts/run-grounding-benchmark.sh).

### P6 — Portfolio release (in progress; evidence packaging partially complete)

**Goal:** turn the working repository into a reviewable, installable case study.

Implemented in this phase:

- `scripts/verify.sh` provides reproducible unsigned test, Debug/Release build,
  hygiene, and analysis steps; the macOS CI workflow is checked in but no
  hosted run is claimed.
- `docs/CASE_STUDY.md`, `docs/INTERVIEW_TALK_TRACK.md`, and the
  capture-ready `docs/DEMO_SCRIPT.md` explain the architecture, evidence rules,
  failure path, and screenshot/readability checklist.
- The grounding benchmark JSON/Markdown reports and their integrity checksums
  are checked in under `samples/grounding-benchmark/`.

Still pending before calling P6 complete:

- Capture and review the four polished screens and the 60–90 second recording.
- Run and link the first hosted CI job for an exact commit.
- Complete Developer ID signing, notarization, stapling, Gatekeeper checks,
  and artifact checksums using `RELEASE_CHECKLIST.md`.
- Publish a tagged release plus sanitized sample evaluation/retrieval reports.

**Exit gate:** a reviewer can clone and test the source, inspect a hosted build,
watch the demo, and verify a notarized artifact without receiving private data.

### P7 — Bounded eval-driven optimizer (stretch, about 1 week)

**Goal:** demonstrate an agentic improvement loop constrained by evidence.

- Cluster failed tuning cases, permit one model-proposed PromptSpec patch per
  iteration, and enforce fixed iteration/token/time budgets.
- Re-run executable checks and accept a patch only when it improves the tuning
  objective without regressing protected constraints.
- Keep a separate held-out set, preserve every version/trace, and support
  rollback; never expose hidden reasoning or silently self-modify production
  prompts.

**Exit gate:** a recorded run shows the full proposal → evaluation → accept or
reject trace, plus held-out results that make overfitting visible.

## Explicitly deferred

Team accounts, cloud sync, hosted prompt marketplaces, background automation,
billing, broad provider catalogs, and speculative quality scoring remain out of
scope until local documents, traces, and evaluation are reliable.

## Engineering boundaries

- `Domain/` contains framework-light, versioned value types and validation.
- `Networking/` owns Ollama transport and provider abstractions.
- `Services/`, `Comparison/`, and `Evaluation/` own orchestration and checks.
- `Features/` renders state and user intent; it should not parse provider
  responses or infer quality conclusions.
- `Persistence/` and `Tracing/` own portable, validated local data formats.
- A custom non-loopback endpoint is an explicit privacy boundary.
- Hidden reasoning is neither requested nor presented as evidence.

The portfolio evidence chain is: PromptSpec → deterministic compile →
comparison/evaluation → exact mechanical evidence → trace/inspect/export →
inspectable local retrieval.

## Employer-facing skills and evidence

- Swift 5/macOS concurrency: actor-isolated Ollama and local repositories,
  cancellation, bounded execution, and injected deterministic providers.
- Typed product architecture: versioned Codable/Sendable domain values,
  validation, deterministic compilation, and explicit privacy boundaries.
- Evidence engineering: exact JSON scalar checks, reproducible options/timing,
  raw outputs/errors, trace hashes, redaction, and portable exports.
- Retrieval foundations: embedding-model/dimension identity, hybrid ranking,
  provenance, injection-safe envelopes, and transparent recall measurements.

Resume templates (replace placeholders with measured results only):

- “Built a local-first macOS prompt workbench with typed PromptSpec generation,
  deterministic compilation, controlled comparison, and exact evaluation checks;
  verified [N] tests and [BUILD RESULT] on [SDK/DATE].”
- “Implemented inspectable local retrieval over text/Markdown using Ollama
  embeddings, hybrid semantic/lexical/MMR ranking, provenance, and redacted
  trace/export flows; measured [RECALL/COVERAGE] on [FIXTURE].”
