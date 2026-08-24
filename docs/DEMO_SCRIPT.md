# PromptMAXX capture-ready demo script

This 60–90 second shot list demonstrates the evidence loop without claiming
benchmark quality, a hosted CI run, a signed distribution release, or completed
screenshot capture. Keep the camera on the app unless a terminal step is
explicitly listed.

## Before recording

### Environment

In terminal 1, keep Ollama running:

```bash
ollama serve
```

In terminal 2, install the separate generation and embedding models:

```bash
ollama pull phi4-mini:latest
ollama pull nomic-embed-text
```

Use the same installed `phi4-mini:latest` tag for the generation demo and
`nomic-embed-text` for Context Inspector embeddings. Confirm Setup shows the
loopback endpoint `127.0.0.1:11434` and that both models are available before
recording.

### Data reset and capture state

- Prefer a clean macOS test account or a fresh app container for a recording.
  Do not delete a personal library or trace/index file without first making a
  backup.
- If using an existing account, remove only the demo documents/traces through
  the app, confirm the editor is clean, and verify that no private prompt text
  appears in the browser or export panels.
- Prepare one short support-ticket request and one small text/Markdown source;
  avoid personal data, credentials, or model-specific private prompts.
- Use a fixed window size, readable system font size, and a neutral appearance.
  Leave enough width for candidate labels, scalar expected/actual values, and
  trace status without truncation.
- Take a copy of any generated JSON/Markdown export after recording if it will
  be shared; unredacted exports can contain source and model output.

## Main shot list

| Time | Shot/action | Voiceover and evidence |
| --- | --- | --- |
| 0–8s | Open Setup | “The default endpoint is loopback. A custom host is an explicit, visible privacy boundary.” |
| 8–20s | Paste the prepared vague support-ticket request and press ⌘↩ | “The model returns a typed `PromptSpec`; it does not directly replace the source with an opaque answer.” |
| 20–32s | Open Edit Spec and Run Details | “The fields, validation, deterministic compiled output, profile, model, timing, and token metadata are inspectable.” |
| 32–44s | Open Compare Candidates with two pairings | “The same source runs through explicit candidates, sequentially by default, with facts rather than a fabricated winner score.” |
| 44–56s | Open Evaluation Lab and run the fixture | “Both candidates use the selected model and visible generation settings. The fixture checks observable JSON requirements.” |
| 56–64s | Expand one case | “Exact scalar checks distinguish missing paths, wrong types, and wrong values; raw output and errors stay visible.” |
| 64–72s | Open Trace Browser | “The lifecycle, configuration, hashes, and redacted/reveal export make the run inspectable.” |
| 72–81s | Open Context Inspector and copy the envelope | “Text/Markdown retrieval preserves provenance and ranking signals, then passes content as untrusted JSON data. This is inspection, not an answer citation.” |
| 81–90s | Open `samples/grounding-benchmark/` and the held-out Markdown export | “This small retrieval-only measurement keeps tuning and held-out results, fixed defaults, model digest, and one visible limitation; it does not claim answer quality or confidence.” |

If a local model is slow, show the factual timing and continue only when the
screen is readable. Do not edit the recording to imply a successful run that
did not happen.

## One honest failure path

Record this as a short alternate take, not as a hidden setup trick:

1. Stop `ollama serve` or temporarily enter an invalid port in Setup.
2. Attempt a model refresh or refinement.
3. Capture the typed connection/setup error and the unchanged source text.
4. Restore `127.0.0.1:11434`, restart Ollama, and verify the selected model
   before returning to the main take.

This demonstrates that unavailable-provider behavior is visible and no guessed
prompt or fabricated evaluation result is substituted. If the failure take is
not recorded, say so rather than presenting it as a captured result.

## Screenshot checklist

Capture status is intentionally incomplete until these are actually recorded:

- [ ] Setup with loopback label and model list visible.
- [ ] Original/refined editor with the prepared non-sensitive request.
- [ ] Edit Spec showing typed fields and validation state.
- [ ] Run Details showing profile/model/options and factual metrics.
- [ ] Compare Candidates showing stable candidate labels and status.
- [ ] Evaluation Lab showing exact check details, raw output/error, and export
      controls.
- [ ] Trace Browser showing lifecycle/configuration and redacted content.
- [ ] Context Inspector showing source/chunk provenance and the copied
      untrusted envelope, without private source text.
- [ ] Tuning and held-out Markdown/JSON benchmark exports with the exact
      timestamped filenames and documented limitation.
- [ ] Honest failure take showing the typed setup/transport error.

Do not add screenshots to the repository or describe screenshot capture as
complete until each checked item has been reviewed for privacy and readability.

## Accessibility and readability pass

Before sharing a recording or still:

- Check every visible label, candidate ID, case ID, status, error, and scalar
  value at the intended presentation size; widen or zoom rather than relying
  on truncated text.
- Ensure color is not the only status cue; status text and icons should remain
  understandable in grayscale or reduced contrast.
- Keep keyboard focus and button labels visible when demonstrating ⌘↩, export,
  cancellation, or copy actions.
- Confirm text selection/copy content does not include hidden credentials or
  unintended neighboring fields.
- Review captions/transcript terminology: say “ranking signal,” “mechanical
  check,” and “untrusted data,” not “confidence,” “truth,” or “citation.”
- Test the alternate failure path with VoiceOver or keyboard navigation if the
  recording claims accessibility behavior; otherwise leave that claim out.

## Measured-result placeholders

Replace these only after a repeatable local run and retain the export alongside
the recording notes:

```text
Original pass rate: [MEASURED ORIGINAL PASS RATE]
Refined pass rate: [MEASURED REFINED PASS RATE]
Mean latency: [MEASURED LATENCY]
Grounding recall@k / source coverage: [MEASURED RETRIEVAL RESULTS]
Environment/model tags: [MEASURED ENVIRONMENT]
```

Signing, notarization, hosted CI evidence, and final screenshot status remain
release/presentation work. See [CASE_STUDY.md](CASE_STUDY.md) and
[INTERVIEW_TALK_TRACK.md](INTERVIEW_TALK_TRACK.md) for the supporting portfolio
narrative.
