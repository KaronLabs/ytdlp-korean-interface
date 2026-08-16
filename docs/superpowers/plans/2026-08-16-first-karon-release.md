# First KaronLabs Binary Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, smoke-test, package, checksum, and publish `v2.19.1-karon.1` as the first KaronLabs Windows x64 GitHub Release, with no release/tag publication before every local gate succeeds.

**Architecture:** Reuse the existing sealed candidate builder and localhost smoke. Add one focused release helper for fixed release metadata, upstream runtime bootstrap, final package inventory/ZIP validation, and publication preparation; add one Windows GitHub Actions workflow whose final phase uses the repository-scoped `GITHUB_TOKEN` to create a draft release for the exact source SHA, attach verified assets, publish it, and reread the public release state. A source-controlled request record triggers the one-time first release only after implementation tests are green.

**Tech Stack:** Windows PowerShell 5.1, GitHub Actions Windows runner, existing C++/MSBuild/CMake/v143 build tooling, 7-Zip, Python, GitHub CLI/REST authenticated with `GITHUB_TOKEN`, SHA-256.

## Global Constraints

- Release tag: `v2.19.1-karon.1`.
- Release title: `ytdlp-korean-interface v2.19.1-karon.1`.
- Platform: Windows x64 only.
- Direct upstream: `ErrorFlynn/ytdlp-interface v2.19.1`.
- Upstream baseline commit: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`.
- Upstream normal Windows x64 archive SHA-256: `53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e`.
- Public ZIP: `ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip`.
- Public checksum asset: `SHA256SUMS.txt`.
- Existing `candidate-manifest.json` remains the authoritative sealed-candidate inventory.
- `release-manifest.json` is the authoritative final extracted-package inventory after license/provenance documents are added.
- Headless GitHub smoke may prove artifact/runtime success but must not claim machine-proven GUI interaction.
- No long-lived PAT, SSH private key, or signing private key is added.
- The release workflow uses minimum required GitHub token permissions: `contents: write` only.
- A failed build, seal, smoke, package, or checksum gate creates no public release or release tag.
- A pre-existing `v2.19.1-karon.1` tag or release is never overwritten or deleted.

---

## File Structure

- Create `tools/release-factory.ps1` — fixed first-release configuration, upstream parent-runtime bootstrap, smoke orchestration, final package manifest/ZIP/checksum verification, and publication-state helpers.
- Create `tests/powershell/release-factory.Tests.ps1` — behavior-level tests for fixed metadata, path/inventory rejection, SHA verification, exact-source binding, and no-clobber publication policy.
- Create `.github/workflows/release-v2.19.1-karon.1.yml` — Windows release orchestration and final GitHub publication transaction.
- Create `release/requests/v2.19.1-karon.1.json` only after all implementation/contract tests are green — one-time release trigger and pinned public inputs.
- Create `release/notes/v2.19.1-karon.1.md` — source-controlled release notes used verbatim by the workflow.
- Modify `PROVENANCE.md` and `CITATION.cff` only after the published release exists and is verified, to replace the current “no KaronLabs release yet” state with factual release metadata.
- Modify `README.md` only after publication verification, adding a real KaronLabs Releases/download path rather than a speculative link.

---

### Task 1: Release Factory Contract and Package Boundary

**Files:**
- Create: `tests/powershell/release-factory.Tests.ps1`
- Create: `tools/release-factory.ps1`

**Interfaces:**
- Produces: `Get-FirstReleaseConfiguration`, `Read-ReleaseRequest`, `Assert-ReleaseRequest`, `Assert-ReleaseSourceRevision`, `Assert-ReleaseDoesNotExist`, `New-ReleasePackage`, `Test-ReleasePackage`, `Write-ReleaseChecksum`, `Test-ReleaseChecksum`.
- Consumes: existing `candidate-manifest.psm1`, `build-candidate.ps1`, `smoke-localhost.ps1`.

- [ ] **Step 1: Write failing release-contract tests**

Tests must prove these behaviors before implementation exists:

```powershell
$config = Get-FirstReleaseConfiguration
Assert-Equal 'v2.19.1-karon.1' $config.Tag
Assert-Equal '53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e' $config.UpstreamArchiveSha256.ToLowerInvariant()
Assert-Throws { Assert-ReleaseRequest -Request @{ tag = 'v2.19.1-karon.2' } } 'release_request_invalid'
Assert-Throws { Test-ReleasePackage -PackageRoot $rootWithUnexpectedFile } 'release_package_inventory_mismatch'
Assert-Throws { Test-ReleasePackage -PackageRoot $rootWithTraversalManifest } 'release_manifest_invalid'
Assert-Throws { Test-ReleaseChecksum -ZipPath $zip -ChecksumPath $wrongChecksum } 'release_checksum_mismatch'
```

Also test that release/package metadata records an exact 40-character source SHA and that caller input cannot change canonical repository, tag, upstream repository, upstream tag, upstream baseline commit, public asset names, or platform.

- [ ] **Step 2: Run the focused PowerShell test and verify RED**

Run on Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/powershell/release-factory.Tests.ps1
```

Expected: FAIL because `tools/release-factory.ps1` and its functions do not yet exist.

- [ ] **Step 3: Implement fixed configuration and request validation**

Use internal constants, not caller-selectable deployment metadata:

```powershell
function Get-FirstReleaseConfiguration {
    [pscustomobject]@{
        Tag = 'v2.19.1-karon.1'
        Title = 'ytdlp-korean-interface v2.19.1-karon.1'
        Repository = 'KaronLabs/ytdlp-korean-interface'
        UpstreamRepository = 'ErrorFlynn/ytdlp-interface'
        UpstreamTag = 'v2.19.1'
        UpstreamCommit = '2173316ebb5e50af49a2a4e939693fa8c3a3459c'
        UpstreamAssetName = 'ytdlp-interface.7z'
        UpstreamArchiveSha256 = '53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e'
        PackageName = 'ytdlp-korean-interface-v2.19.1-karon.1-win-x64'
        ZipName = 'ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip'
        ChecksumName = 'SHA256SUMS.txt'
        Platform = 'win-x64'
    }
}
```

`Read-ReleaseRequest` parses JSON using UTF-8 and rejects malformed/extra policy-changing values. `Assert-ReleaseSourceRevision` requires `GITHUB_SHA`/supplied source SHA to match `^[0-9a-f]{40}$`, verifies `git rev-parse HEAD`, and requires a clean worktree.

- [ ] **Step 4: Implement final package manifest and checksum validation**

`New-ReleasePackage` copies only the sealed candidate payload plus `LICENSE`, `NOTICE`, and `PROVENANCE.md`. It creates `release-manifest.json` with source/upstream/candidate/smoke/yt-dlp metadata and an exact inventory excluding the manifest itself.

`Test-ReleasePackage` reparses the manifest and requires:

```text
all paths relative
no .. traversal
no absolute paths
no .git/build/smoke/temp paths
no duplicate entries
listed files == actual files excluding release-manifest.json
SHA-256 and length match every listed file
candidate-manifest.json digest matches the supplied reviewed digest
```

Create the ZIP only after package validation, reopen it with .NET `System.IO.Compression.ZipArchive`, require exactly one expected top-level directory, and reject unexpected entries. `Write-ReleaseChecksum` writes exactly:

```text
<lowercase-64-hex>  ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip
```

- [ ] **Step 5: Run focused tests and verify GREEN**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/powershell/release-factory.Tests.ps1
```

Expected: all release-factory contract tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add tools/release-factory.ps1 tests/powershell/release-factory.Tests.ps1
git commit -m "feat: add release package verification boundary"
```

---

### Task 2: Verified Parent Runtime, Candidate Build, and Artifact Smoke

**Files:**
- Modify: `tools/release-factory.ps1`
- Modify: `tests/powershell/release-factory.Tests.ps1`

**Interfaces:**
- Produces: `New-VerifiedUpstreamParentRuntime`, `Invoke-ReleaseCandidateBuild`, `Invoke-ReleaseArtifactSmoke`.
- Consumes: upstream x64 archive, `runtime-maintenance.psm1` verified nightly transaction internals or a CI-safe wrapper around the same verification path, `build-candidate.ps1`, `smoke-localhost.ps1`.

- [ ] **Step 1: Add failing parent-runtime tests**

Cover:

```powershell
Assert-Throws { Assert-UpstreamArchiveHash -Path $tamperedArchive } 'upstream_archive_hash_mismatch'
Assert-Throws { Resolve-UpstreamRuntimeRoot -ExtractedRoot $ambiguousTree } 'upstream_runtime_ambiguous'
Assert-Throws { Resolve-UpstreamRuntimeRoot -ExtractedRoot $incompleteTree } 'upstream_runtime_incomplete'
```

Require exactly one extracted directory containing `ytdlp-interface.exe`, `yt-dlp.exe`, `ffmpeg.exe`, `ffprobe.exe`, `deno.exe`, `7z.dll`, and `ytdlp-interface.json`.

- [ ] **Step 2: Verify RED**

Run the focused test file and confirm failure on missing parent-runtime functions.

- [ ] **Step 3: Implement verified upstream runtime extraction**

Download only the fixed ErrorFlynn release asset URL derived from the fixed repository/tag/asset configuration. Verify SHA-256 before extraction. Use a trusted Program Files `7z.exe`; extraction occurs under a unique runner temp directory. Reject reparse points, traversal-like extracted names, ambiguity, and incomplete runtime payloads.

- [ ] **Step 4: Establish official nightly provenance without weakening user updater policy**

First test whether the GitHub-hosted Windows process is elevated. The public `UpdateYtDlp` must remain unchanged and must continue to reject elevated interactive use.

For release CI only, reuse the module's private verified metadata + `Invoke-YtDlpTransaction` path inside module scope against the disposable extracted parent runtime. Do not remove or bypass checksum/version/backup/provenance/rollback verification; bypass only the public interactive `Test-IsElevated` entry gate because the target is an isolated runner-local copy.

The resulting parent runtime must contain `yt-dlp-provenance.json` whose repository is `yt-dlp/yt-dlp-nightly-builds`, channel is `nightly`, current hash/tag match `yt-dlp.exe`, and rollback backup hash/version match the recorded previous values. Reuse `build-candidate.ps1`'s existing `Get-VerifiedParentRuntime` as the final authority.

- [ ] **Step 5: Invoke existing sealed candidate builder**

Call:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-candidate.ps1 `
  -Run `
  -SourceRoot $SourceRoot `
  -ParentRuntime $ParentRuntime `
  -CandidateBase $CandidateBase `
  -DependencyArchiveDirectory $SourceRoot
```

Parse the returned `CandidateRoot` and `ManifestPath`, require both under the expected temp base, hash `candidate-manifest.json`, and re-run the shared candidate seal validator.

- [ ] **Step 6: Add and run the artifact-only localhost smoke**

Dot-source `smoke-localhost.ps1` and pass an automation command that uses the execution copy's own `yt-dlp.exe` and FFmpeg against the exact `127.0.0.1` URL:

```powershell
$automation = {
    param($url, $candidateRoot, $outputDirectory, $guiPid)
    $ytDlp = Join-Path $candidateRoot 'yt-dlp.exe'
    $template = Join-Path $outputDirectory 'smoke.%(ext)s'
    & $ytDlp --ignore-config --no-playlist --ffmpeg-location $candidateRoot -x --audio-format mp3 -o $template $url
    if ($LASTEXITCODE -ne 0) { throw 'release_smoke_download_failed' }
    [pscustomobject]@{ Completed = $true; GuiProcessId = $guiPid; Url = $url; OutputDirectory = $outputDirectory }
}
```

Snapshot the smoke evidence `runs` directory before/after execution. Require exactly one new successful `artifact-only` evidence record bound to the candidate manifest SHA, with `artifactValidated=true`, `guiInteractionProven=false`, valid output hash/length/duration, and clean process cleanup. Hash that evidence JSON for the release manifest.

- [ ] **Step 7: Run focused and existing PowerShell suites**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1
```

Expected: all PowerShell tests pass; network/build integration remains reserved for the release workflow itself.

- [ ] **Step 8: Commit Task 2**

```bash
git add tools/release-factory.ps1 tests/powershell/release-factory.Tests.ps1
git commit -m "feat: build and smoke verified release candidates"
```

---

### Task 3: Release Notes and Publication Workflow

**Files:**
- Create: `release/notes/v2.19.1-karon.1.md`
- Create: `.github/workflows/release-v2.19.1-karon.1.yml`
- Modify: `tests/powershell/release-factory.Tests.ps1`

**Interfaces:**
- Workflow consumes the fixed request record and calls `tools/release-factory.ps1`.
- Publication consumes only the already-verified ZIP, `SHA256SUMS.txt`, exact source SHA, and source-controlled release notes.

- [ ] **Step 1: Add failing workflow/static contract tests**

Read the YAML/notes as text and require:

```text
runs-on: windows-2022
permissions -> contents: write and no write-all
checkout exact github.sha
path-scoped request trigger
no release command before build/smoke/package verification step
GH_TOKEN sourced from github.token/secrets.GITHUB_TOKEN
release target is exact source SHA
release is not prerelease
notes disclose direct upstream
notes include exact verification filenames
```

Also assert the workflow never uses `--clobber`, force tag updates, a PAT secret, or an SSH private key.

- [ ] **Step 2: Verify RED**

Run `release-factory.Tests.ps1`; expect failure because workflow and notes are absent.

- [ ] **Step 3: Write concise release notes**

Include:

```markdown
# ytdlp-korean-interface v2.19.1-karon.1

Windows x64 Korean recovery/hardening release based on ErrorFlynn/ytdlp-interface v2.19.1.

Highlights: Korean source recovery, validated ko-KR catalog with English fallback, presentation/state separation, runtime maintenance and rollback hardening, candidate attestation, localhost artifact smoke.

Verification: compare the ZIP against SHA256SUMS.txt; inspect release-manifest.json and candidate-manifest.json inside the archive.

Bundled yt-dlp: official nightly build identified exactly in release-manifest.json.

작은 일이었는데 작지 않게 됐습니다.
```

Do not imply KaronLabs authored unchanged ErrorFlynn/yt-dlp code and do not claim headless GUI interaction proof.

- [ ] **Step 4: Implement workflow preflight/build/package job**

The job must:

1. checkout exact `${{ github.sha }}`;
2. prove checked-out SHA equals `${{ github.sha }}` and worktree is clean;
3. validate request JSON against fixed configuration;
4. verify tag/release absence using GitHub API/CLI;
5. verify runner prerequisites (`powershell.exe`, trusted 7-Zip, Python, MSBuild/v143/CMake through existing builder discovery, and GitHub CLI if publication uses it);
6. run parent bootstrap, build, candidate seal, artifact smoke, final package validation, ZIP reopening, and checksum validation;
7. only after all those succeed enter publication.

- [ ] **Step 5: Implement publication transaction**

Use repo-scoped `GITHUB_TOKEN` with `permissions: contents: write` and `GH_TOKEN` only for the publication phase.

Preferred commands:

```powershell
gh release create $tag $zipPath $checksumPath `
  --repo $env:GITHUB_REPOSITORY `
  --target $sourceSha `
  --title $title `
  --notes-file $notesPath `
  --draft

gh release edit $tag --repo $env:GITHUB_REPOSITORY --draft=false --latest
```

Before `gh release create`, re-check that both tag and release are absent. On a failure before publish, reread release/tag state and clean up only objects created by the current run and only when the release is still draft/unpublished. On uncertain state after publish request, preserve the object and reread rather than blindly deleting/recreating it.

After publication, run `gh release view` and require `isDraft=false`, `isPrerelease=false`, exact tag/title, and exactly the two intended assets. Download the published ZIP and checksum to a fresh directory, rerun `Test-ReleaseChecksum`, and inspect the downloaded ZIP/package manifest again. This final download verification proves the bytes GitHub serves, not only the local pre-upload files.

- [ ] **Step 6: Verify workflow/static tests GREEN**

Run the full PowerShell suite and Python contracts.

- [ ] **Step 7: Commit Task 3**

```bash
git add .github/workflows/release-v2.19.1-karon.1.yml release/notes/v2.19.1-karon.1.md tests/powershell/release-factory.Tests.ps1
git commit -m "ci: add verified first release factory"
```

---

### Task 4: Trigger the First Release and Verify Public Bytes

**Files:**
- Create: `release/requests/v2.19.1-karon.1.json`

**Interfaces:**
- The request file is the one-time push trigger for `.github/workflows/release-v2.19.1-karon.1.yml`.

- [ ] **Step 1: Re-run all pre-trigger repository checks**

Run/observe:

```text
Python contract suite -> PASS
PowerShell suite -> PASS
Deploy SSH security contract -> PASS
Provenance contract -> PASS
Release factory static/behavior contracts -> PASS
```

Do not create the request file while any check is red.

- [ ] **Step 2: Create the fixed release request**

```json
{
  "schemaVersion": 1,
  "tag": "v2.19.1-karon.1",
  "platform": "win-x64",
  "upstreamRepository": "ErrorFlynn/ytdlp-interface",
  "upstreamTag": "v2.19.1",
  "upstreamCommit": "2173316ebb5e50af49a2a4e939693fa8c3a3459c",
  "upstreamAsset": "ytdlp-interface.7z",
  "upstreamArchiveSha256": "53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e"
}
```

Commit message:

```bash
git add release/requests/v2.19.1-karon.1.json
git commit -m "release: request v2.19.1-karon.1"
```

- [ ] **Step 3: Observe the release workflow to completion**

Do not infer success from a created tag. Inspect the job and logs. Required evidence:

```text
upstream archive SHA gate PASS
verified nightly provenance PASS
candidate build PASS
candidate seal PASS
artifact-only localhost smoke PASS
release package inventory PASS
ZIP SHA PASS
draft creation/assets PASS
publish PASS
fresh public download verification PASS
workflow conclusion success
```

If the run fails, follow `superpowers:systematic-debugging`; fix the root cause, rerun repository tests, and retrigger using a new request commit only if the workflow trigger semantics require it. Never manually fabricate the release to bypass a failed gate.

- [ ] **Step 4: Verify public GitHub release state independently**

Fetch the release by tag and verify:

```text
tag_name == v2.19.1-karon.1
draft == false
prerelease == false
assets == ZIP + SHA256SUMS.txt
ZIP asset digest/size are nonempty
published release source/tag resolves to the intended request commit
```

Download both public assets and verify the checksum and internal manifests one more time.

- [ ] **Step 5: Commit factual post-release metadata**

Only after the public release is verified:

- update `PROVENANCE.md` current canonical release from `None yet` to `v2.19.1-karon.1`, recording its exact release source SHA;
- add `version: v2.19.1-karon.1` and `date-released` to `CITATION.cff`, while preserving accurate upstream boundaries;
- add a real KaronLabs Release/download section to `README.md`.

Run provenance contracts; update their expectations only to accept the now-real release, never to weaken provenance requirements.

- [ ] **Step 6: Final verification**

Use `superpowers:verification-before-completion`. Freshly verify:

```text
release exists and is public
public assets match checksums
internal release manifest validates
all repository contract tests green
release workflow successful
provenance docs refer to the real release only
```

- [ ] **Step 7: Commit post-release documentation**

```bash
git add README.md PROVENANCE.md CITATION.cff tests/contract/test_provenance_contract.py
git commit -m "docs: record first verified KaronLabs release"
```

---

## Plan Self-Review

- Spec coverage: build, upstream SHA pinning, parent runtime, official nightly provenance, sealed candidate, artifact smoke, package manifest, ZIP checksum, draft publication, public reread/download verification, and factual post-release docs are each assigned to explicit tasks.
- No placeholder requirements remain.
- Release identifiers and function names are consistent across tasks.
- Public publication is intentionally separated from implementation commits; the request file is not created until tests are green.
- The public user updater's unelevated-policy behavior is preserved. CI may reuse the same private verified nightly transaction only against a disposable isolated parent runtime, and that CI-specific boundary must be tested/documented rather than weakening `UpdateYtDlp`.
