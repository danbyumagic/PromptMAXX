# Comparison and Evaluation methodology

PromptMAXX separates candidate comparison from mechanical evaluation. Both
surfaces expose observations and configuration; neither claims to identify a
universally “best” prompt or model.

## Candidate comparison

The Compare Candidates setup accepts 2–4 unique model/profile pairings for one
source prompt. It validates non-empty IDs, models, profiles, and duplicate
pairings. Results retain input order even when bounded concurrent batches
complete out of order.

The UI uses sequential, resource-aware execution (`maxConcurrent = 1`) by
default. The core runner supports bounded concurrency for controlled tests or
future workflows. Each result can report:

- pending, running, completed, failed, or cancelled status;
- attempts when the refinement engine exposes them;
- compiled output or validation failure;
- provider error, start/end times, TTFT/latency, and token counts.

There is intentionally no quality score. A reviewer must inspect the source,
profile, compiled output, errors, and metrics together.

## Evaluation Lab

The built-in suite is `support-ticket-json-v1`, version 1, with eight fixed
support-ticket inputs. Each case has structural checks plus exact JSON scalar
checks for known owner/priority facts. Exact checks distinguish missing paths,
wrong types, and mismatched values with evidence-rich details. These are
mechanical checks, not human preference judgments.

The Lab compares two candidates on the same selected installed model:

- Original extraction instruction.
- Refined extraction instruction with an explicit JSON field contract.

Both use the same deterministic provider configuration: temperature `0.2`,
top-p `0.9`, max tokens `512`, seed `42`, streaming enabled, and JSON format.
The UI displays those settings so the instruction change is not confused with
a sampling change.

The report presents, in candidate order:

- passed cases and pass rate;
- average latency, input tokens, and output tokens;
- per-case check labels/details, raw output, errors, and timing.

Latency includes runtime and possible model warm-up. It is useful for
comparative observation on the same machine, not an absolute quality metric.

## Reproducibility and export

The evaluation report includes the suite and version, candidate IDs/labels,
models, instructions, generation options, timestamps, per-case outputs,
checks, errors, and available token/latency metadata. The Lab exports the
complete report as pretty-printed JSON or Markdown through a macOS save panel.
Filenames are sanitized and timestamped.

Comparison and evaluation are still affected by model version, quantization,
hardware, Ollama version, available memory, prompt wording, and endpoint
configuration. The fixture is intentionally small and support-ticket-specific;
it does not estimate general prompt quality, semantic correctness beyond its
checks, or human usefulness.

## Limitations and bias controls

- Required-field and JSON checks favor outputs that follow the fixture’s
  contract; they do not reward nuance outside that contract.
- Eight cases cannot represent a production workload.
- Same settings control sampling, but model implementations and runtime state
  still differ.
- A fixed seed is a reproducibility aid, not a guarantee across model builds or
  hardware.
- Warm-up and local resource contention influence latency.
- Pass rate is descriptive evidence, not a decision rule or winner selection.
- Human review remains necessary before adopting a compiled prompt.
