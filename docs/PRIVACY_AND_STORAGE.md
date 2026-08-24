# Privacy, storage, backup, and recovery

PromptMAXX is local-first by default, not local-only under every configuration.

## Network boundary

The default Ollama endpoint is `http://127.0.0.1:11434`. Setup displays whether
the configured endpoint is local or remote. A non-loopback host is an explicit
boundary: source text, system instructions, model names, and generation
requests are sent to that server according to its network policy.
PromptMAXX constructs HTTP Ollama endpoints and does not terminate TLS. Use a
trusted network or an encrypted tunnel when configuring a non-loopback host.

The networking layer does not add a cloud provider or telemetry service. The
app uses Ollama’s `/api/tags`, `/api/generate`, and `/api/embed` APIs.
Grounding is text/Markdown-only and records embedding model plus vector
dimension so indexes are not silently mixed.
The user remains responsible for the privacy policy and access controls of a
custom endpoint.

## Settings

The current UI stores these preferences through `UserDefaults`:

- `ollamaHost`
- `ollamaPort`
- `selectedModel`
- `selectedProfileID`
- `systemPrompt`

`UserDefaults` is OS-managed; the app does not present it as a portable prompt
library or an encrypted secret store. Do not put credentials or sensitive
material into the editable system prompt unless that is acceptable for the
machine’s local account.

## Local app data

The repositories ask `FileManager` for the user Application Support directory,
then use these logical paths:

```text
PromptMAXX/prompt-library.json
PromptMAXX/prompt-library.json.bak
PromptMAXX/traces.json
PromptMAXX/grounding-<endpoint-sha256>.json
```

For a signed sandboxed build, macOS maps that directory inside the application
container, typically:

```text
~/Library/Containers/dbyup.PromptMAXX/Data/Library/Application Support/PromptMAXX/
```

An unsigned development build may instead resolve it directly under:

```text
~/Library/Application Support/PromptMAXX/
```

Grounding uses an endpoint-scoped filename so vector spaces from different
Ollama hosts cannot be mixed. The opaque suffix is derived from the validated endpoint.
Because Ollama embed responses do not include a model digest, an embedding tag
updated in place may require an explicit index rebuild.
If an index is corrupt or unsupported, the app preserves the bytes and requires
an explicit user-confirmed discard/reset; it does not silently replace them.

The prompt-library repository validates the existing store before replacement, writes through
an atomic temporary file, and preserves a last-known-good backup. Corrupt or
unreadable primary data is not silently overwritten. Recovery is explicit and
preserves the corrupt primary beside the recovered file. Import rejects invalid
data before writing. The legacy `promptHistory` UserDefaults payload is kept as
a migration source until a successful versioned save.

## Traces and exports

`RunTrace` captures provider/model, endpoint label/locality, profile and
generation options, status, metrics, hashes, errors, and factual stage events.
`TraceRepository` accepts an injected URL, supports filtering, retention,
atomic writes, and redacted JSON export. The editor persists meaningful
refinement, comparison, and evaluation outcomes through `TraceStore`; transient
UI interactions are not treated as durable runs. Trace Browser makes stored
lifecycle evidence inspectable and supports explicit redaction/reveal export.

Evaluation exports are user-initiated through save panels. JSON contains the
complete report; Markdown includes configuration, timestamps, checks, errors,
and raw outputs. Review an export before sharing because unredacted reports can
contain the original prompt and model output.

## Practical review checklist

Before sending content to a custom endpoint or sharing an export:

1. Confirm the endpoint label and host in Setup.
2. Remove secrets and personal data from the source prompt where possible.
3. Review raw outputs and errors in the report.
4. Use redacted trace export where appropriate; note that evaluation export is
   intentionally complete and is not a redaction mechanism.
