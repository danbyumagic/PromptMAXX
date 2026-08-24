# PromptMAXX release checklist

This is a procedure, not a claim that signing or notarization has been
completed. The repository currently verifies unsigned builds only.

## Verified before release

- [ ] Confirm the supported matrix: macOS 26.0+, Xcode 26, Swift 5 mode.
- [ ] Run the unsigned Debug build and full test suite.
- [ ] Run the unsigned Release build.
- [ ] Review `CHANGELOG.md`, README, known limitations, and demo script.
- [ ] Test loopback Ollama setup, missing server, missing model, invalid
      endpoint, cancellation, comparison cancellation, and evaluation export.
- [ ] Pull both `phi4-mini:latest` (generation) and `nomic-embed-text`
      (embedding); verify Context Inspector import, retrieve, provenance,
      endpoint-scoped index identity, and explicit corrupt-index discard/reset.
- [ ] Review the checked-in retrieval evidence in
      `samples/grounding-benchmark/README.md`, including both JSON/Markdown
      reports, the fixed configuration, held-out limitation, and retrieval-only
      interpretation; rerun with `scripts/run-grounding-benchmark.sh` if
      changing the corpus, model, or retrieval defaults.
- [ ] Inspect exported JSON/Markdown for accidental private prompt content.
- [ ] Confirm version/build values in Xcode: currently marketing version 1.0,
      build 1, bundle identifier `dbyup.PromptMAXX`.

## Signing and archive

- [ ] Select the intended Developer ID Application team and provisioning
      profile; do not rely on Automatic signing without reviewing the result.
- [ ] Confirm App Sandbox settings and Outgoing Connections (Client) entitlement
      for Ollama HTTP requests, plus User Selected File read/write access for
      explicit import/export save panels.
- [ ] Archive the Release configuration with signing enabled.
- [ ] Export a Developer ID `.app` or `.dmg` and record the archive checksum.
- [ ] Verify the signed bundle, entitlements, bundle identifier, version, and
      architecture on a clean Mac.

## Notarization and distribution

- [ ] Submit the signed artifact to Apple notarization using the team’s secure
      credentials.
- [ ] Wait for an accepted notarization result; retain the submission ID.
- [ ] Staple the ticket to the distributed artifact.
- [ ] Run Gatekeeper assessment on a clean supported macOS installation.
- [ ] Recalculate and publish SHA-256 checksums with release notes.
- [ ] Attach the signed artifact, changelog, Ollama setup instructions, and
      privacy boundary to the release.
- [ ] Record rollback/revocation steps and the next supported-version review.
