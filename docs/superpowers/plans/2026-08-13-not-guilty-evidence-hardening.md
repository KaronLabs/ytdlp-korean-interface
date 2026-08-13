# NOT GUILTY Evidence Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Korean i18n recovery independently reviewable with a complete, non-overwriting evidence chain.

**Architecture:** Preserve the existing candidate workflow and add narrow proof boundaries around update rollback, build inputs, and smoke outputs. Automated smoke proves an artifact; a separately supervised interaction proves GUI behavior.

**Tech Stack:** PowerShell 5.1, C++/MSBuild v143, Python unittest, Git, FFmpeg/FFprobe.

## Global Constraints

- Do not edit or delete the existing `review/spec_20260813_130912_korean_i18n_recovery.md`.
- Do not overwrite the preserved parent runtime.
- Existing dependency source directories are read-only from this workflow.
- Only `127.0.0.1` synthetic media may be used for smoke tests.
- Every behavior change follows Red-Green-Refactor with output retained for the resubmission.

---

### Task 1: Runtime provenance transaction

**Files:**
- Modify: `tests/powershell/runtime-maintenance.Tests.ps1`
- Modify: `tools/runtime-maintenance.psm1`
- Modify: `tools/build-candidate.ps1`
- Modify: `docs/runtime-maintenance.md`

**Interfaces:**
- Produces a provenance manifest containing `previousVersion`, prior backup hash,
  and a recoverable journal around executable/provenance commit.

- [x] **Step 1: Write four failing public/state-boundary tests**

Add these behavior tests to `tests/powershell/runtime-maintenance.Tests.ps1`:

1. `Test-UpdateYtDlpRecoversPendingTransactionBeforeMetadataFetch` seeds a
   new executable, new provenance, old backup, and pending journal; forces the
   metadata fetch to fail; then asserts the public update already restored the
   exact old executable/provenance pair and removed the journal.
2. `Test-RecoveryRejectsPreviousVersionMismatchBeforeMutation` seeds a
   hash-valid backup with a journal version that does not match it; it asserts
   an error and byte-for-byte preservation of the live executable, provenance,
   and journal.
3. `Test-RecoveryRejectsMalformedProvenancePreimageBeforeMutation` uses invalid
   Base64 and asserts the same fail-before-mutation result.
4. `Test-YtDlpTransactionWhatIfDoesNotRecoverPendingJournal` invokes the
   transaction with `-WhatIf` and asserts the live pair and journal remain
   byte-for-byte unchanged.

- [x] **Step 2: Verify RED**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/powershell/runtime-maintenance.Tests.ps1`

Expected: all four tests fail for their intended state mutation/order reason,
not for fixture setup or syntax.

- [x] **Step 3: Implement minimally**

Move confirmed public recovery before metadata staging/network access. Skip
recovery under `-WhatIf`. Parse and validate the entire journal, decode the
provenance preimage, and verify backup hash and version before mutating either
live file. Restore and verify the complete pair before deleting the journal.

- [x] **Step 4: Verify GREEN**

Run the same fixture and the full PowerShell test runner. Expected: zero failures.

- [ ] **Step 5: Extend the crash-state table**

Add passing boundary cases for pre-replace journal recovery, post-provenance
recovery, missing-backup rejection, and idempotent replay. These do not replace
the four mandatory RED observations.

### Task 2: Candidate build attestation

**Files:**
- Modify: `tests/powershell/smoke-localhost.Tests.ps1`
- Modify: `tools/build-candidate.ps1`
- Modify: `docs/windows-smoke.md`

**Interfaces:**
- `candidate-manifest.json.attestation` binds a Git revision/status, archive,
  linker-library hashes, toolchain identities, and normalized build commands.

- [ ] **Step 1: Write failing tests**

Add controlled fixtures proving that an existing dependency tree cannot skip
archive verification and that a manifest missing an attestation field fails.

- [ ] **Step 2: Verify RED**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/powershell/smoke-localhost.Tests.ps1`

Expected: an assertion failure naming the archive bypass or omitted attestation field.

- [ ] **Step 3: Implement minimally**

Always verify the supplied archive before use, record source and toolchain
identity, and hash each actual Release x64 dependency library before product
assembly. Do not alter existing dependency trees.

- [ ] **Step 4: Verify GREEN**

Run the fixture and full PowerShell test runner. Expected: zero failures.

### Task 3: Run-unique localhost smoke evidence

**Files:**
- Modify: `tests/powershell/smoke-localhost.Tests.ps1`
- Modify: `tools/smoke-localhost.ps1`
- Modify: `docs/windows-smoke.md`

**Interfaces:**
- Each run emits `smoke-evidence/runs/<run-id>.json` with mode, candidate
  manifest hash, output MP3 hash/size/duration, and stable outcome code.

- [x] **Step 1: Write failing seal and lifecycle tests**

Add behavior fixtures proving:

1. the exact manifest bytes accepted by the caller have the caller-supplied
   expected SHA-256 and are the only bytes parsed for copying;
2. duplicate paths, malformed hashes/lengths, missing required runtime files,
   extra unmanifested candidate files, and path traversal are rejected;
3. the execution derivative records a separate settings-overlay hash and its
   base files still validate against the sealed candidate manifest immediately
   before launch;
4. the entire sealed candidate tree is identical before and after a smoke run;
5. cleanup failure is recorded and reported even when the run was already
   failing;
6. evidence distinguishes `artifactValidated`, `guiInteractionProven`,
   `operatorAttested`, and `cleanupSucceeded`; a direct-output automation
   scriptblock can never set GUI proof;
7. two run IDs use `CreateNew` evidence files and cannot overwrite one another.

- [x] **Step 2: Verify RED**

Run the smoke fixture. Expected: failures naming the execution-manifest
mismatch, candidate-tree mutation, missing trusted manifest anchor, swallowed
cleanup failure, and absent proof-level fields.

- [x] **Step 3: Implement minimally**

Snapshot and authenticate the manifest once, validate its complete inventory,
then copy/verify the sealed base. Store run settings as a separately hashed
derivative instead of presenting a mutated file as manifest-matching. Put all
smoke evidence outside `CandidateRoot`. Use a Downloads-contained unique root,
create a tone-and-color synthetic MP4, and write sanitized run-unique evidence
with distinct artifact, GUI, operator, and cleanup proof fields.

- [x] **Step 4: Verify GREEN**

Run all PowerShell fixtures. Expected: zero failures.

- [x] **Step 5: Preserve successful GUI artifacts before cleanup**

Before deleting a successful workspace, atomically copy the MP3 body, final
settings JSON, FFprobe output, and no-`.part` inventory into the external
run-evidence directory. Record every retained relative path, SHA-256, length,
and UTC timestamp in the run manifest. A forced process termination is not
evidence that settings survived a normal GUI close.

### Task 4: Package and final gates

**Files:**
- Create: `review/spec_<timestamp>_korean_i18n_recovery_resubmission.md`
- Modify: `locales/ko-KR.json` (line ending normalization only)

- [ ] **Step 1: Run all deterministic suites and `git diff --check`**

Record command, cwd, UTC timestamps, exit code, and transcript hash for each gate.

- [ ] **Step 2: Fresh candidate build and supervised GUI smoke**

Record the build log, candidate manifest hash, run-unique smoke manifest, FFprobe JSON, and supervised GUI observations. Do not claim GUI success without the actual current-run interaction record.

- [ ] **Step 3: Assemble append-only resubmission package**

Include exact diff inventory, threat model, risk handling, and artifacts sufficient for a different session to reproduce the ruling.
