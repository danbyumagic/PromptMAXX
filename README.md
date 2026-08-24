# PromptMAXX

PromptMAXX is a focused macOS prompt workbench: turn a rough request into a
structured, editable prompt, inspect what changed, compare controlled
candidates, and measure mechanical checks against a fixed fixture set.

Its product thesis is an inspectable evidence loop rather than “one more chat
box”:

1. Generate a typed `PromptSpec` from rough source text.
2. Validate it locally and compile it deterministically.
3. Run the same source through controlled model/profile candidates.
4. Evaluate observable requirements and retain raw evidence.
5. Export results so a reviewer can inspect the configuration and failures.

The default provider is Ollama at `127.0.0.1:11434`. A custom endpoint is
supported, but it is an explicit privacy boundary: prompts and model requests
leave the Mac when the configured host is not loopback.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?style=flat-square)
![Swift 5](https://img.shields.io/badge/Swift-5.0-orange?style=flat-square)
![License MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

## Implemented now

- Dual-pane original/refined editor with local history and keyboard shortcuts.
- Typed `OllamaEndpoint`, actor-isolated `OllamaClient`, streaming generation,
  HTTP/error validation, explicit timeouts, and cancellation mapping.
- Structured `PromptSpec` generation with schema validation, deterministic
  compilation, profile selection, editable spec review, and one corrective
  retry for malformed/invalid model output.
- Built-in profiles: Concise, Structured, Preserve Voice, and Custom.
- Candidate comparison for 2–4 unique model/profile pairings, sequential by
  default for local resource safety, with factual status/attempt/latency/token
  metadata and no fabricated quality score.
- Evaluation Lab with eight support-ticket cases, same-model original/refined
  candidates, controlled deterministic generation settings, mechanical JSON
  checks, per-case evidence, and JSON/Markdown export.
- Versioned prompt-library and run-trace stores with atomic writes,
  backup/recovery paths, validation, hashes, redaction, and browser surfaces.
- Grounding Context Inspector for UTF-8 text/Markdown sources up to 10 MiB: local chunking,
  Ollama `/api/embed`, model/dimension identity, hybrid semantic+lexical+MMR
  retrieval, provenance, and an untrusted-data envelope. It does not generate
  answers or claim citations.
- Checked-in grounding retrieval evidence: a small 10-query tuning split and
  10-query held-out split with JSON/Markdown exports, fixed configuration, and
  explicit retrieval-only limitations. See
  [the benchmark evidence](samples/grounding-benchmark/README.md).

## Quick start with Ollama

Requires macOS 26 or later and Xcode 26 for source builds.

```bash
brew install ollama
ollama serve
```

Keep `ollama serve` running, then use a second terminal:

```bash
ollama pull phi4-mini:latest
ollama pull nomic-embed-text
```

`phi4-mini:latest` is the generation model; `nomic-embed-text` is the separate
embedding model used by Context Inspector.

Open PromptMAXX. Setup defaults to `127.0.0.1` port `11434`; select an
installed model in the editor toolbar. The Settings scene (⌘,) validates the
endpoint, refreshes models, edits the system prompt, and opens diagnostics.

To use another Ollama server, enter its host and decimal port in Setup. Treat
that endpoint as remote unless it is a validated loopback address. PromptMAXX's
Ollama transport is HTTP, so use a trusted network or encrypted tunnel for a
remote host.

## Workflow and evidence

The main editor’s Details menu exposes Edit Spec, Run Details, Compare
Candidates, and Evaluation Lab. A typical review flow is:

1. Enter a rough support or product request.
2. Refine it with a selected model/profile and inspect the generated spec.
3. Edit the spec if needed; the compiled prompt is regenerated locally.
4. Compare 2–4 model/profile pairings without ranking them.
5. Run the Evaluation Lab to inspect pass counts, timing, token metadata,
   exact check labels, raw output, and errors. Inspect retrieved context and
   provenance in Context Inspector when grounding is enabled, then export
   evaluation or trace evidence as JSON/Markdown.

Evaluation pass rates are mechanical checks, not subjective quality judgments.
Latency includes runtime and possible model warm-up, so it should be compared
carefully rather than treated as an absolute quality measure.

## Architecture

The component boundaries and data flow are documented in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The short version is:

```text
SwiftUI editor → RefinementEngine → ModelProvider → OllamaClient → Ollama
       ↓                  ↓                  ↓
 PromptSpec        local validation     streamed chunks
       ↓
 PromptCompiler → comparison / evaluation → exact evidence → traces/inspect/exports
       ↘ GroundingStore → chunk/index → hybrid retrieval → untrusted envelope
```

The provider boundary keeps Ollama-specific transport out of the domain and
allows deterministic injected-provider tests.

## Privacy and storage

- Ollama traffic defaults to loopback. A non-loopback host sends prompt text,
  system instructions, and generation requests to that configured server.
- User settings are stored through `UserDefaults` keys for host, port, model,
  profile, and system prompt.
- The durable prompt library uses the app's
  `Application Support/PromptMAXX/prompt-library.json`; its backup is
  `prompt-library.json.bak`. A signed sandboxed build resolves this inside the
  app container. The repository writes atomically and exposes explicit recovery
  rather than silently replacing corrupt data.
- Legacy `promptHistory` defaults data can be migrated into the versioned
  library after a successful save.
- Trace repositories accept an injected file URL, support filtering and
  redacted export; meaningful refinement, comparison, and evaluation outcomes
  are persisted explicitly, while transient UI interactions are not runs.

See [docs/PRIVACY_AND_STORAGE.md](docs/PRIVACY_AND_STORAGE.md) for the trust
boundary, recovery behavior, and what is not currently persisted by the app.

## Build and test

The project uses Swift 5 mode and targets macOS 26.0. The verified local
commands use the installed macOS 26.5 SDK and disable signing:

```bash
xcodebuild -project PromptMAXX.xcodeproj -scheme PromptMAXX \
  -configuration Debug -sdk macosx26.5 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

xcodebuild -project PromptMAXX.xcodeproj -scheme PromptMAXX \
  -configuration Debug -sdk macosx26.5 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test

xcodebuild -project PromptMAXX.xcodeproj -scheme PromptMAXX \
  -configuration Release -sdk macosx26.5 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

On 2026-08-18, the local suite passed all 164 tests, both unsigned Debug and
universal Release builds succeeded, and static analysis passed with Xcode 26.5
on macOS 26.5.2. The repository also contains a GitHub Actions workflow that
runs the same verification entry point on `macos-latest`; this README does not
claim a hosted CI run for any particular commit.

## Portfolio demo: 60–90 seconds

1. Start Ollama and show Setup’s loopback privacy notice.
2. Paste a vague support-ticket request and press ⌘↩.
3. Open Edit Spec; point out typed fields, validation, and deterministic
   compiled output.
4. Open Compare Candidates; select two pairings and call out sequential,
   resource-aware execution and the absence of a quality score.
5. Open Evaluation Lab, select one installed model, run the fixture, and show
   identical visible generation settings plus exact JSON scalar evidence; export
   the report as Markdown or JSON.
6. Open Trace Browser, reveal/redact a run, then open Context Inspector to show
   source provenance, ranking signals, and the untrusted-data envelope; copy
   the envelope for inspection rather than implying a grounding export.
7. Open the checked-in grounding benchmark Markdown export and call out the
   tuning/held-out split, fixed defaults, and the q-heldout-10 limitation.
8. Close with the custom-endpoint warning and the known limitation that checks
   are mechanical, model-dependent, and not a universal quality test.

## Known limitations

- Ollama must be installed, running, and able to load the selected model.
- Model output, availability, latency, and JSON compliance vary by model and
  hardware; no quality winner is inferred.
- Evaluation is a small eight-case support-ticket fixture with exact JSON scalar,
  structural, and required-field checks, not a broad benchmark or human review.
- Grounding accepts UTF-8 text/Markdown files up to 10 MiB: PDF extraction, answer citations/RAG
  generation, and an LLM judge are intentionally absent.
- Retrieval scores are semantic similarity, lexical overlap, and MMR diversity
  signals—not confidence or correctness claims.
- Live grounding/evaluation requires local Ollama and the selected models.
- Custom remote Ollama endpoints use HTTP; PromptMAXX does not terminate TLS.
- CI workflow configuration exists, but no hosted run is claimed here.
- Signing, notarization, stapling, and distribution are release tasks, not
  completed artifacts in this repository.

## Further reading

- [Architecture and data flow](docs/ARCHITECTURE.md)
- [Comparison and Evaluation methodology](docs/EVALUATION.md)
- [Privacy, storage, backup, and recovery](docs/PRIVACY_AND_STORAGE.md)
- [60–90 second demo script](docs/DEMO_SCRIPT.md)
- [Release checklist](RELEASE_CHECKLIST.md)
- [Portfolio roadmap and status](PORTFOLIO_ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Contributing and verification](CONTRIBUTING.md)

## License

MIT
