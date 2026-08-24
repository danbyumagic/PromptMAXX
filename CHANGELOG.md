# Changelog

## 1.0.0-portfolio (unreleased)

This portfolio packaging describes the current implementation; it is not a
signed or notarized distribution release.

### Added

- Typed, validated Ollama endpoint and actor client with streaming generation,
  timeouts, HTTP status handling, typed errors, and cancellation.
- Structured PromptSpec generation, validation, deterministic compilation,
  profile selection, corrective retry, spec editing, and run details.
- Controlled 2–4 candidate comparison with sequential local-safe defaults,
  stable ordering, factual metrics, and no fabricated quality score.
- Evaluation Lab for the eight-case support-ticket fixture with same-model
  deterministic settings, mechanical checks, evidence inspection, and complete
  JSON/Markdown export.
- Integrated versioned prompt-library and run-trace stores with validation,
  atomic persistence, backup/recovery, hashes, filtering, Trace Browser, and
  redacted trace export.
- Text/Markdown grounding with Ollama `/api/embed`, model/dimension identity,
  deterministic chunking, hybrid retrieval, provenance, untrusted envelopes,
  and Context Inspector.
- Checked-in retrieval-only grounding benchmark reports for tuning and
  held-out splits, including model digest, dimensions, ranking configuration,
  JSON/Markdown exports, and a documented held-out limitation.
- Portfolio documentation for architecture, methodology, privacy/storage,
  demo flow, and release procedure.

### Verification observed

- On 2026-08-18, all 164 tests passed, unsigned Debug and universal Release
  builds succeeded, and static analysis passed with Xcode 26.5 on macOS 26.5.2.
- Signing, notarization, hosted CI, and public distribution remain unchecked.
