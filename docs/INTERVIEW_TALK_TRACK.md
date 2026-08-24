# PromptMAXX interview talk track

Use this as a five-minute explanation after the short demo. It is written in
first person so the presenter can answer from the implementation rather than
from generic AI claims.

## Opening: the product decision

“I built PromptMAXX because prompt refinement is easy to demo and hard to
review. A polished final string does not tell me which model or profile made
it, whether the structure was valid, or whether a cancelled run wrote a late
result. I designed the app as a local-first evidence loop: typed PromptSpec,
deterministic compilation, controlled candidate runs, mechanical checks, and
inspectable traces and exports.”

## Architecture in one minute

“The SwiftUI views handle intent and presentation. Domain types such as
`PromptSpec`, profiles, evaluation cases, and run records are versioned and
validated without networking. `ModelProvider` and `EmbeddingProvider` are
small async boundaries, so Ollama is an adapter rather than the domain. The
actor-isolated `OllamaClient` handles endpoint validation, HTTP status, NDJSON,
timeouts, and cancellation. Repositories and `TraceStore` validate and write
portable local JSON atomically.”

“A typical request flows from rough source to a typed JSON spec, through local
validation and deterministic compilation, then into comparison/evaluation.
The outcome is turned into a factual trace with configuration, timestamps,
metrics, errors, and hashes. Grounding is a separate text/Markdown path using
an embedding provider and a provenance-preserving untrusted envelope.”

## Reliability choices worth highlighting

“I do not let a model response directly become editor state. The refinement
request asks for the app-owned JSON format, disables thinking output, and
delimits source text as data. The stream is reassembled and decoded into a
`PromptSpec`; only valid specs compile. There is one bounded corrective retry,
not an unbounded repair loop.”

“For async UI work, each run captures a token. The token and cancellation state
are checked before building a trace and again before persistence. Evaluation
cases that were already committed remain, while a superseded callback cannot
append a late trace. Trace appends are serialized so concurrent terminal
callbacks do not get dropped as a busy conflict.”

## Why these evaluations instead of an LLM judge?

“The built-in evaluation is intentionally mechanical. It uses a small,
versioned support-ticket fixture and checks JSON structure plus exact scalar
facts such as owner and priority. A missing path, wrong scalar type, and wrong
value produce different evidence. That makes a failure inspectable and
deterministic. It does not claim that passing the fixture means the prompt is
universally better, so human review remains part of the workflow.”

“If I report a pass rate, latency, recall, or source coverage, I show the
fixture, model/tag, options, environment, and export alongside it. I never
invent a metric to make the demo look stronger.”

## Grounding and RAG boundary

“Grounding is retrieval infrastructure, not answer generation. The importer
currently accepts text and Markdown. Chunks preserve source ranges and
provenance; embeddings are validated for dimension and finite values; ranking
combines semantic similarity, lexical overlap, and MMR diversity. Those are
relevance signals, not confidence.”

“Retrieved text is untrusted data. The Context Inspector JSON-encodes chunk
content and provenance inside a marked envelope, so a document containing the
end marker stays a field value. There is no PDF extraction, answer citation,
or LLM judge in this version.”

## Failure and privacy answer

“The default endpoint is loopback, but local-first is not the same as local-only.
If a user configures a custom host, PromptMAXX sends prompts and model requests
over HTTP to that host and does not terminate TLS. I make that boundary visible
and recommend a trusted network or encrypted tunnel. Local library, trace, and
grounding files are validated and written atomically; corrupt data is not
silently overwritten.”

“If Ollama is unavailable, the app shows a typed setup/transport error. If
structured output remains invalid after the bounded retry, it stays a failure.
If the user cancels, cancellation is not mislabeled as a server error. These
are product behaviors, not hidden fallback guesses.”

## Questions I expect

### Why Swift actors?

“Ollama streaming and local persistence both cross suspension points. Actors
make the client/repository state explicit, while injected sessions/providers
keep tests deterministic. UI state remains main-actor isolated.”

### Why not compare only final text?

“Final text loses provenance. Candidate configuration, profile version,
options, timings, status, and errors are needed to tell whether a difference
came from instructions, model, sampling, or a failed run.”

### What would you add next?

“I would first broaden measured fixtures and capture repeatable results, then
polish the text/Markdown grounding inspector. PDF extraction, answer
generation/citations, a subjective judge, cloud sync, and distribution signing
are deliberately separate scope decisions—not features I would imply are
already present.”

### What is not finished?

“The repository has local unsigned build/test evidence, but signing,
notarization, hosted CI results, and screenshot capture are not presented as
completed. Any portfolio metric remains a placeholder until I can attach the
exact run and environment.”

## Close

“The main outcome is not that the model always wins. It is that a reviewer can
follow what happened, reproduce the configuration locally, inspect failures,
and see where privacy and product boundaries are. That is the engineering
value I would carry into a larger AI product.”
