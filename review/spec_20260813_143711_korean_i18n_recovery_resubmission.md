# Korean i18n recovery - evidence-hardening resubmission

## meta

- created_at: 2026-08-13T14:37:11Z
- review_target: worktree based on commit `b28e0bc43e70e27cc5d50b89b08aa23b259cf26b` on `codex/korean-i18n-recovery`
- comparison_base: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`
- supersedes: `review/spec_20260813_130912_korean_i18n_recovery.md` (SHA-256 `BC2552D3A6BBFFBAC42232549DE093B304D34E96D3BEBAB69A816742C6681F4C`)
- base_diff_inventory: 25 added, 29 modified, 0 deleted (`git diff --name-status 2173316e..b28e0bc`)
- reviewer_access_assumption: repository read access plus the candidate and parent runtime paths listed below; no reliance on prior chat state
- changed_files_or_diff: `git diff -- docs/runtime-maintenance.md docs/windows-smoke.md locales/ko-KR.json tests/powershell/runtime-maintenance.Tests.ps1 tests/powershell/smoke-localhost.Tests.ps1 tests/run_powershell_tests.ps1 tools/build-candidate.ps1 tools/runtime-maintenance.psm1 tools/smoke-localhost.ps1`, plus the two design/plan files under `docs/superpowers/`
- evidence_package:
  - spec_file_content: this complete file
  - changed_files_or_diff: command above, with `git diff --check` evidence below
  - test_logs_or_evidence_quotes: E1 through E6
  - relevant_runtime_outputs: candidate manifest, smoke run manifest, migrated parent provenance, and retained original provenance migration backup
  - constitution_path: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\AGENTS.md`

## scope and corrections

This append-only resubmission addresses the prior review's evidence-integrity findings without editing the original spec.

1. `runtime-maintenance.psm1` now writes a sibling transaction journal before executable replacement. A subsequent update restores executable and exact provenance preimage from a residual journal, verifies prior hash/version, and only then removes the journal.
2. `smoke-localhost.ps1` verifies every candidate-manifest file hash and creates a Downloads-contained execution copy. Only that copy receives the smoke outpath; the sealed candidate and its manifest remain unchanged.
3. A successful smoke manifest now requires 64-hex candidate/output hashes, a relative output path, and positive file length/duration. Per-run manifests use `FileMode.CreateNew`.
4. Parent provenance now requires `previousVersion`, `previousSha256`, and a backup path whose hash matches. The existing legacy parent provenance was migrated only after running its pre-existing backup from a temporary `.exe` copy; the original provenance bytes were retained in a timestamped migration backup. No executable was replaced and no network download occurred.
5. Candidate assembly now copies a source snapshot excluding pre-existing dependency roots and `.git` into an isolated short-path workspace before extracting the reviewed dependency archive. Candidate attestation enumerates all four dependency configure/build commands plus product MSBuild with source-root paths normalized as `<source>`.
6. FFprobe parser input normalizes Windows CRLF before matching `codec_name=mp3` and duration. The actual integration failure was reproduced with a CRLF test before this change.
7. Residual-journal recovery verifies the recorded backup SHA-256 before it can overwrite the current target; a corrupt-backup RED fixture proves the refusal path.

## threat model delta

- An in-process exception between EXE and provenance commits leaves a journal for restart recovery, which verifies both historical executable identity and provenance preimage. Power-loss durability of the journal itself is not claimed because this implementation does not call `Flush(true)`.
- A smoke run cannot silently modify the candidate that its manifest names. The original candidate manifest hash binds the sealed input; the execution copy is transient under the run workspace.
- The local HTTP server remains explicitly `127.0.0.1`. No external URL, credential, browser profile, proxy, or download archive participates.
- Arbitrary AutomationCommand output is still `artifact-only`; it cannot establish GUI causality. Only a supervised operator/Computer Use recording can establish GUI interactions.

## tests

### E1 - PowerShell regression perimeter

- command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1`
- timestamp: 2026-08-13T15:13:42.9560503Z
- raw log: `review/evidence/powershell-tests-20260813T1514Z.log`
- output:
  ```text
  runtime-maintenance tests passed
  PASS runtime-maintenance.Tests.ps1
  smoke-localhost fixture tests passed.
  PASS smoke-localhost.Tests.ps1
  ```

Coverage includes residual-journal recovery, exact provenance preimage restoration, legacy provenance rejection, sealed candidate preservation, append-only manifests, required success evidence, and CRLF FFprobe output.

### E2 - i18n contract perimeter

- command: `$env:RECOVERED_CATALOG='locales/ko-KR.json'; <bundled-python> tests/run_contract_tests.py`
- timestamp: 2026-08-13T15:14:02.9315079Z
- raw log: `review/evidence/python-contract-tests-20260813T1514Z.log`
- output:
  ```text
  Ran 20 tests in 7.484s
  OK
  ```

### E3 - native i18n executable

- command: `tests/native/x64/Debug/i18n_tests.exe`
- timestamp: 2026-08-13T15:17:57.9976329Z
- raw log: `review/evidence/native-i18n-tests-20260813T1518Z.log`
- output: `NATIVE_EXIT=0`

### E4 - whitespace gate

- command: `git diff --check`
- timestamp: 2026-08-13T15:14:02.9015086Z
- raw log: `review/evidence/git-diff-check-20260813T1514Z.log`
- output: exit code 0 (Git emitted line-ending conversion warnings only)

### E5 - parent provenance migration

- command: run pre-existing backup from a temporary `.exe` copy, verify SHA-256, atomically replace provenance after preserving original bytes
- timestamp: 2026-08-13T14:30Z
- output:
  ```text
  PROVENANCE_MIGRATED_PREVIOUS_VERSION=2026.05.16.233954
  PROVENANCE_MIGRATED_PREVIOUS_SHA256=0B6BD5752A3C66F3FB781EF0601501F5FD3ECE2A4A57BD98FB19B08EE860786B
  ```
- runtime output: current parent provenance retains the original current nightly hash/version and records the prior backup identity; original provenance is at `yt-dlp-provenance.json.migration-backup-20260813143000.1f5b7d251caa490a9679c9cbeabececf`.

### E6 - fresh candidate and artifact-only localhost smoke

- build command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-candidate.ps1 -Run -SourceRoot <src> -ParentRuntime <parent> -DependencyArchiveDirectory <src> -CandidateBase <temp>`
- build timestamp: candidate manifest `createdAtUtc=2026-08-13T15:11:21.9291912Z`
- build output: `review/build-candidate-isolated.out.log` records the returned `CandidateRoot` and `ManifestPath`. A residual MSBuild process remained after that return and was terminated; therefore this package does not assert an independently captured builder process exit code.
- candidate root: `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-candidates\candidate-76c0809270b046a8b79f706bcf740419`
- candidate manifest SHA-256: `254FF77E1C19BC1E3D4DC59AE98DBAF4876BF03839DF1295421B77012BAD182B`
- independent manifest audit: 8 runtime-file hashes, 4 linker-input hashes, reviewed dependency archive SHA-256 `6D50D1F74978CFAB8E40439487D67EF21A4B43E31CFB00EE95D23AEDFC791BAE`, source commit `b28e0bc43e70e27cc5d50b89b08aa23b259cf26b`, and six normalized commands were read back after assembly.
- command attestation: six entries (bit7z, Nana, libpng, libjpeg-turbo configure/build, product MSBuild); no absolute source path present.
- smoke command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand <script: Invoke-LocalhostSmoke -PythonPath C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe -AutomationCommand <candidate yt-dlp localhost extraction>>`
- smoke timestamp: 2026-08-13T15:17:11.3023732Z
- smoke output:
  ```text
  SMOKE_ARTIFACT_EXIT=0
  succeeded: true
  reasonCode: ok
  mode: artifact-only
  output.sha256: 188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5
  output.length: 9328
  output.duration: 2.020136
  ```
- smoke manifest: `smoke-evidence/runs/9a8ad8aaf5c34e7983f370a358c18166.json` (SHA-256 `5EA1A0B259D9314247582F3289CF3DC9C3E9230CC9A6A15C4BAAD6D72B471E77`)
- verification: smoke evidence records the same candidate manifest SHA-256 as the independent audit. The first explicit smoke attempt failed with `python_missing`; it was rerun with the verified Python 3.12.13 absolute path and then passed.

## risks

- description: GUI-internal URL entry, info lookup, MP3 selection, and download-click behavior remain unproven.
  - severity: high
  - handling: accepted_unresolved - Computer Use initialization failed before window enumeration with `EPERM: operation not permitted, lstat 'C:\\Users\\ceo\\AppData\\Local\\OpenAI\\Codex'`. Directory existence, normal ACL inheritance, and lack of reparse points were verified read-only. Artifact-only evidence does not substitute for GUI proof.
- description: candidate attestation records `dirty: true` because this resubmission is an uncommitted worktree.
  - severity: medium
  - handling: safeguard - the candidate manifest records the exact dirty status; commit the reviewed diff and rebuild a clean candidate before release/approval.
- description: the isolated candidate exists and runs successfully, but the build wrapper timeout and empty redirected logs mean its original process exit code is not independently available.
  - severity: medium
  - handling: accepted_unresolved - the manifest was independently audited and the candidate passed a fresh artifact-only localhost smoke; rebuild under a durable job runner and retain its final process exit log before release approval.
- description: elevated wrapper reports a PowerShell profile execution-policy warning after child commands complete.
  - severity: low
  - handling: accepted_unresolved - all actual test/build/smoke children were explicitly `-NoProfile -ExecutionPolicy Bypass` and returned their recorded exit codes.

## status

partial_success

## reviewer request

Review the current diff and rerun E1-E6. Do not issue GUI approval unless a different session/model can create a supervised GUI record that proves Korean startup, URL entry, information lookup, MP3 selection, completed download, fresh MP3, FFprobe output, and the required DPI observations. Until then this package deliberately remains `partial_success`.
