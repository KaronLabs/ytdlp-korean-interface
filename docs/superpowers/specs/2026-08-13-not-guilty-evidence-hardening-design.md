# NOT GUILTY Evidence Hardening Design

## Goal

Close the review findings against the Korean i18n recovery without changing the
preserved parent runtime. The candidate build, runtime update transaction, and
localhost smoke must each emit bounded, reproducible evidence rather than
self-attested summaries.

## Selected design

1. Runtime update records the previous executable version and restores both the
   executable and pre-existing provenance when the provenance commit fails. A
   sibling journal makes an interrupted two-file update recover on the next
   update attempt.
2. Candidate build always verifies the reviewed dependency archive when the
   caller supplies one, rejects an unverified existing-dependency bypass, and
   writes a manifest attestation containing source revision/dirty state,
   archive identity, dependency library hashes, build commands, and toolchain
   identities. Existing dependency roots are never deleted or overwritten.
3. Localhost smoke verifies the sealed candidate manifest, copies the verified
   candidate files into a unique smoke root under the current user's Downloads
   Known Folder, changes only the execution copy's output path, and writes one
   append-only manifest per run. Automated markers
   prove an artifact-only run; GUI acceptance remains reserved for a supervised
   operator or Computer Use record.
4. The resubmission package supersedes, but never edits,
   `review/spec_20260813_130912_korean_i18n_recovery.md`. It records exact diff
   inventory, commands, timestamps, exit codes, transcript hashes, and artifact
   hashes.

## Security and evidence boundaries

- The smoke server binds only `127.0.0.1`; it uses no external media, cookies,
  proxy, browser profile, or download archive.
- Absolute runtime paths and localhost URLs do not appear in published smoke
  manifests; run identifiers and candidate manifest hashes bind the evidence.
- An arbitrary PowerShell automation scriptblock cannot claim GUI causality.
  Its manifest mode is `artifact-only`.
- `File.Replace` provides the atomic primitive for one file. The update journal
  supplies recovery for the executable/provenance pair.

## Verification perimeter

- PowerShell fixtures prove each new transaction, attestation, and smoke
  behavior with a RED failure before production edits.
- Python contract tests retain the i18n and artifact-ignore perimeter.
- Native i18n tests retain the C++ localization boundary.
- The final package includes a fresh Release x64 build log, candidate manifest,
  run-unique FFprobe evidence, and a supervised GUI smoke record.

## Test coverage perimeter

The verdict is divided into six independently provable boundaries. A green
result in one boundary is not evidence for another.

| Boundary | Required observable evidence | Explicit negative cases |
| --- | --- | --- |
| Runtime pair transaction | The executable and provenance converge to the complete old pair after every interrupted pre-commit state, before any metadata/network operation | corrupt journal shape, malformed provenance preimage, backup hash mismatch, backup version mismatch, missing backup with mismatched live target, `-WhatIf` with a pending journal |
| Candidate seal | Every assembled file is length/hash bound to one manifest and the build log records the direct child exit code | unverified archive, dirty/unbound source, missing linker input, manifest path traversal, extra or mismatched candidate bytes |
| Smoke derivative | The sealed candidate is byte-for-byte unchanged; only a run-unique execution copy receives a run output path | mutation of sealed settings, stale MP3, `.part`, non-MP3 codec, zero duration, cleanup timeout, duplicate run id |
| Localization contracts | 524 non-empty Korean strings have exact active-call parity; state logic is independent of visible captions | missing key, orphan key, empty fallback, malformed settings, caption-dependent state branch |
| Native executable | The compiled i18n/state test binary exits `0` from the reviewed source/build | compiler/build failure or any native assertion failure |
| GUI acceptance | One candidate-manifest hash binds startup, all translated pages/dialogs, state transitions, settings JSON persistence, the complete localhost MP3 flow, and 100/150/200% DPI observations | localization-error dialog, untranslated required control, caption-dependent behavior, output escape, stale output, `.part`, invalid JSON, clipped/unusable required control at any DPI |

Runtime recovery must be exercised through the public `UpdateYtDlp` ordering,
not only by calling an internal recovery helper. The public-path test must prove
that a pending transaction is healed even when the following metadata fetch
fails. Recovery validation is fail-before-mutation: every journal field,
provenance preimage, backup hash, and backup version is validated before either
member of the live pair changes. `-WhatIf` never heals or removes a journal.

GUI evidence is causal rather than declarative. An `artifact-only` marker or an
operator typing `YES` proves neither a click nor a visible state. Each required
GUI action is followed by a fresh Computer Use observation, and the ledger
records the returned window identity and candidate-manifest hash.
