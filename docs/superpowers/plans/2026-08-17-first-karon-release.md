# First KaronLabs Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, smoke-test, package, checksum, and publish `v2.19.1-karon.1` as the first Windows x64 KaronLabs GitHub Release, with no tag or release created unless every pre-publication gate succeeds.

**Architecture:** Add a focused PowerShell release helper plus one Windows GitHub Actions workflow. The helper bootstraps a verified upstream parent runtime, reuses `build-candidate.ps1` and `smoke-localhost.ps1`, assembles a release package with `release-manifest.json`, validates the ZIP and checksum, then the workflow publishes exactly two assets only after all local gates pass.

**Tech Stack:** PowerShell 7 / Windows GitHub Actions / existing Visual Studio v143 build scripts / `gh` CLI / GitHub Releases / SHA-256 / 7-Zip.

## Global Constraints

- Release tag is exactly `v2.19.1-karon.1`.
- Release title is exactly `ytdlp-korean-interface v2.19.1-karon.1`.
- Platform is Windows x64 only.
- Direct upstream baseline is `ErrorFlynn/ytdlp-interface v2.19.1`, commit `2173316ebb5e50af49a2a4e939693fa8c3a3459c`.
- Upstream x64 runtime archive SHA-256 is `53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e`.
- Public ZIP is exactly `ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip`.
- Public checksum asset is exactly `SHA256SUMS.txt`.
- No public tag or Release may exist before build, candidate seal, artifact smoke, package manifest validation, ZIP validation, and checksum validation have all succeeded.
- A pre-existing release or tag named `v2.19.1-karon.1` is a hard failure and is never overwritten.
- Headless smoke is described as artifact/runtime smoke; it must not claim machine-proven GUI interaction.
- No long-lived PAT, SSH private key, or signing private key is introduced.

---

### Task 1: Release package contract and helper tests

**Files:**
- Create: `tests/powershell/release-factory.Tests.ps1`
- Create: `tools/release-factory.ps1`

**Interfaces:**
- Consumes: repository root, fixed release metadata, candidate directory, smoke evidence.
- Produces: `New-ReleasePackage`, `Assert-ReleasePackage`, `Write-ReleaseChecksums`, and fixed release metadata helpers used by the workflow.

- [ ] **Step 1: Write failing tests for fixed release identity and package rejection rules**

Create tests that dot-source `tools/release-factory.ps1` and assert:

```powershell
$metadata = Get-KaronReleaseMetadata
Assert-True ($metadata.Tag -ceq 'v2.19.1-karon.1') 'wrong release tag'
Assert-True ($metadata.ZipName -ceq 'ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip') 'wrong zip name'
Assert-True ($metadata.UpstreamArchiveSha256 -ceq '53B54E3C5C753E8CB2A8B9638C69C95C1449C8185C3145A9F0B06A2000B3702E') 'wrong upstream digest'
```

Add fixtures proving package validation rejects:

```text
../escape.txt
C:\absolute.txt
unexpected.tmp
extra unmanifested files
duplicate manifest entries
hash mismatch
missing required runtime file
```

- [ ] **Step 2: Run the focused test and verify RED**

Run on Windows:

```powershell
pwsh -NoProfile -File tests/powershell/release-factory.Tests.ps1
```

Expected: FAIL because `tools/release-factory.ps1` does not exist.

- [ ] **Step 3: Implement minimal release package helper**

`tools/release-factory.ps1` must be inert when dot-sourced and expose functions for tests. `Get-KaronReleaseMetadata` returns fixed metadata; package assembly copies the sealed candidate payload plus `LICENSE`, `NOTICE`, and `PROVENANCE.md`; `release-manifest.json` inventories every package file except itself with normalized relative path, byte length, and SHA-256. Validation reparses the manifest and rejects absolute/traversing/duplicate/missing/extra/hash-mismatched entries.

- [ ] **Step 4: Verify focused tests GREEN**

Run:

```powershell
pwsh -NoProfile -File tests/powershell/release-factory.Tests.ps1
```

Expected: all release package contract tests pass with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add tools/release-factory.ps1 tests/powershell/release-factory.Tests.ps1
git commit -m "feat: add release package contract"
```

---

### Task 2: Verified parent runtime bootstrap and release build command

**Files:**
- Modify: `tools/release-factory.ps1`
- Modify: `tests/powershell/release-factory.Tests.ps1`

**Interfaces:**
- Consumes: exact upstream asset URL/expected SHA, repository root, source-controlled dependency archive.
- Produces: `Initialize-ReleaseParentRuntime` and `Invoke-KaronReleaseBuild` returning candidate root, candidate manifest path, and candidate manifest SHA-256.

- [ ] **Step 1: Add failing tests for upstream archive digest and ambiguous extraction**

Tests must prove `Initialize-ReleaseParentRuntime` rejects:

```text
wrong archive SHA-256
zero matching runtime roots
multiple matching runtime roots
runtime missing required files
```

and accepts exactly one runtime root containing the expected upstream runtime payload.

- [ ] **Step 2: Run focused tests and verify RED for missing functions**

```powershell
pwsh -NoProfile -File tests/powershell/release-factory.Tests.ps1
```

- [ ] **Step 3: Implement bootstrap**

Implementation must:

```text
Download ErrorFlynn v2.19.1 ytdlp-interface.7z
→ hash before extraction
→ inspect/extract with Program Files 7-Zip
→ resolve exactly one runtime root
→ invoke existing UpdateYtDlp against that isolated parent copy
→ require yt-dlp-provenance.json
→ call existing build-candidate.ps1 -Run
```

The helper must never modify a preserved operator runtime.

- [ ] **Step 4: Verify tests GREEN**

Run the same focused test suite and confirm exit 0.

- [ ] **Step 5: Commit**

```bash
git add tools/release-factory.ps1 tests/powershell/release-factory.Tests.ps1
git commit -m "feat: bootstrap verified release runtime"
```

---

### Task 3: Automated artifact/runtime smoke gate

**Files:**
- Modify: `tools/release-factory.ps1`
- Modify: `tests/powershell/release-factory.Tests.ps1`

**Interfaces:**
- Consumes: sealed candidate, parent runtime, candidate-manifest SHA-256.
- Produces: `Invoke-KaronReleaseSmoke` and a smoke result containing evidence manifest path/hash.

- [ ] **Step 1: Add failing tests for smoke proof semantics**

Tests must assert that release smoke metadata cannot set `guiInteractionProven=true` in artifact-only mode and that a failed smoke result cannot be passed into package publication preparation.

- [ ] **Step 2: Verify RED**

```powershell
pwsh -NoProfile -File tests/powershell/release-factory.Tests.ps1
```

- [ ] **Step 3: Implement the release automation command**

Use existing `smoke-localhost.ps1` with an automation script block that accepts:

```powershell
param($Url, $CandidateRoot, $OutputDirectory, $GuiPid)
```

It must use the candidate's own `yt-dlp.exe` and FFmpeg path to process the exact `127.0.0.1` smoke URL into the supplied output directory, then return:

```powershell
[pscustomobject]@{
    Completed = $true
    GuiProcessId = $GuiPid
    Url = $Url
    OutputDirectory = $OutputDirectory
}
```

The existing smoke tool remains responsible for MP3 validation, FFprobe, `.part` rejection, evidence retention, and process cleanup.

- [ ] **Step 4: Verify focused tests GREEN**

Run the focused release test suite and confirm exit 0.

- [ ] **Step 5: Commit**

```bash
git add tools/release-factory.ps1 tests/powershell/release-factory.Tests.ps1
git commit -m "feat: gate release on localhost smoke"
```

---

### Task 4: ZIP, checksum, and publication transaction

**Files:**
- Modify: `tools/release-factory.ps1`
- Modify: `tests/powershell/release-factory.Tests.ps1`

**Interfaces:**
- Consumes: validated package directory and exact source SHA.
- Produces: ZIP, `SHA256SUMS.txt`, release notes, and `Publish-KaronRelease`.

- [ ] **Step 1: Add failing publication-safety tests**

Tests must assert:

```text
pre-existing tag → reject
pre-existing Release → reject
checksum file contains one ZIP entry only
publish function cannot be called with unvalidated package state
exact source SHA must be 40 lowercase hex
```

- [ ] **Step 2: Verify RED**

Run focused release tests.

- [ ] **Step 3: Implement archive and publish functions**

The helper must create the ZIP, compute SHA-256, write one-line `SHA256SUMS.txt`, reopen/list the archive, and reject unsafe/unexpected paths. Publication uses `gh` with `GITHUB_TOKEN`, targeting the exact source SHA, creates the Release only after all local gates are complete, uploads exactly the ZIP and checksum file, marks it latest/non-prerelease, then re-reads release metadata to verify published state and asset names.

If publication state is uncertain after a network error, re-read GitHub state before any cleanup. Never overwrite or delete a pre-existing object.

- [ ] **Step 4: Verify focused tests GREEN**

Run focused release tests and confirm exit 0.

- [ ] **Step 5: Commit**

```bash
git add tools/release-factory.ps1 tests/powershell/release-factory.Tests.ps1
git commit -m "feat: package and publish verified release"
```

---

### Task 5: GitHub Actions Release Factory workflow

**Files:**
- Create: `.github/workflows/release-karon.yml`
- Create: `release/requests/v2.19.1-karon.1.json`
- Modify: `tests/powershell/release-factory.Tests.ps1`

**Interfaces:**
- Consumes: push of the fixed request file or manual `workflow_dispatch`.
- Produces: one Windows job that runs tests, build, smoke, package, checksum, and final publication.

- [ ] **Step 1: Add failing static workflow tests**

Assert workflow text contains:

```yaml
permissions:
  contents: write
```

and that the only push path is `release/requests/v2.19.1-karon.1.json`. Assert no `release`, `gh release create`, or tag-writing command appears before the build/smoke/package gate invocation.

- [ ] **Step 2: Verify RED**

Run focused release tests; expected failure because workflow/request do not exist.

- [ ] **Step 3: Create workflow and request**

Workflow requirements:

```text
windows-2022
checkout exact event SHA
run existing Python contract tests
run existing PowerShell fixture tests
run release-factory.Tests.ps1
invoke tools/release-factory.ps1 -Run -SourceSha $env:GITHUB_SHA
contents: write only
failure diagnostic artifact may be uploaded, but never as a Release asset
```

The request JSON pins tag, upstream archive name/SHA, platform, and release title only.

- [ ] **Step 4: Verify static tests GREEN**

Run focused release tests.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release-karon.yml release/requests/v2.19.1-karon.1.json tests/powershell/release-factory.Tests.ps1
git commit -m "ci: add first Karon release factory"
```

This commit intentionally triggers the first release workflow.

---

### Task 6: Observe the real release run and remediate only evidence-backed failures

**Files:**
- Modify only files proven necessary by the workflow failure.

**Interfaces:**
- Consumes: GitHub Actions job/step/log evidence.
- Produces: a successful release workflow and published Release.

- [ ] **Step 1: Observe the triggered workflow to completion or first failure**

Inspect workflow run, jobs, and logs. Do not guess at fixes.

- [ ] **Step 2: If a failure occurs, use systematic debugging**

Identify root cause from the failing step/log, add or refine a regression test where feasible, then make the smallest fix. Repeat until the full release run succeeds.

- [ ] **Step 3: Verify published Release**

Fetch `v2.19.1-karon.1` and assert:

```text
draft=false
prerelease=false
assets exactly:
  ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip
  SHA256SUMS.txt
```

- [ ] **Step 4: Download published assets and verify bytes**

Download both assets from the published Release. Compute SHA-256 of the ZIP and compare it to `SHA256SUMS.txt`. Extract to a temporary directory and run `Assert-ReleasePackage` against the included `release-manifest.json`.

- [ ] **Step 5: Confirm final source and CI state**

Verify the release tag resolves to the intended source SHA and that the release workflow plus existing provenance/deploy-security checks are green for the final source state.

---

### Task 7: Update repository-facing release metadata after publication

**Files:**
- Modify: `PROVENANCE.md`
- Modify: `CITATION.cff`
- Modify: `README.md`
- Modify: `tests/contract/test_provenance_contract.py`

**Interfaces:**
- Consumes: verified published `v2.19.1-karon.1` release metadata.
- Produces: repository docs that no longer say no KaronLabs release exists.

- [ ] **Step 1: Update provenance contract test first**

Change the test from rejecting a Karon release version to requiring the real published tag and canonical Release reference.

- [ ] **Step 2: Verify RED**

Run:

```bash
python tests/run_contract_tests.py
```

Expected: provenance contract fails because docs still describe the Release as nonexistent.

- [ ] **Step 3: Update docs and citation**

`PROVENANCE.md` records the actual canonical release/source SHA. `CITATION.cff` gets `version: v2.19.1-karon.1` and release date only after the Release exists. README Download section points to the canonical Releases page / first Windows x64 release without inventing a direct asset URL before verification.

- [ ] **Step 4: Verify contract tests GREEN**

Run:

```bash
python tests/run_contract_tests.py
```

- [ ] **Step 5: Commit docs**

```bash
git add PROVENANCE.md CITATION.cff README.md tests/contract/test_provenance_contract.py
git commit -m "docs: record first canonical Karon release"
```

---

## Final Verification

Run/confirm all of the following against the final repository state:

```text
release-factory PowerShell tests: PASS
existing PowerShell fixtures: PASS
Python contract tests: PASS
Deploy SSH security contract: PASS
Provenance contract: PASS
Release Factory workflow: PASS
published Release: v2.19.1-karon.1
published assets: exactly ZIP + SHA256SUMS.txt
published ZIP SHA-256: matches checksum asset
extracted release-manifest.json: validates all packaged files
```

Do not report completion if any relevant check is unavailable or failing.