# Korean i18n recovery — final evidence package

## meta

- created_at_utc: `2026-08-13T15:38:00Z`
- review_target: dirty worktree based on `b28e0bc43e70e27cc5d50b89b08aa23b259cf26b` on `codex/korean-i18n-recovery`
- comparison_base: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`
- supersedes: `review/spec_20260813_143711_korean_i18n_recovery_resubmission.md`
- reviewer_access_assumption: repository read access and the files under `review/evidence`; no prior chat state required for deterministic gates
- reviewer_required: a different session or model must inspect the frozen patch and reproduce the GUI flow before release approval
- constitution_path: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\AGENTS.md`
- changed_files_or_diff: `review/evidence/comparison-base-to-worktree-20260813T1535Z.patch`
- frozen_diff_sha256: `4640A5DBD9634F87C8624CDAF1DFD7A97A02BAE2CCBFEFCED567357626F7F2EA`
- worktree_status: `review/evidence/worktree-status-20260813T1535Z.txt`
- evidence_package: `review/evidence/evidence-ledger-20260813T1537Z.json`
- evidence_ledger_sha256: `49A14153C42E1FAE40F3CA82D7C62B9DA8300C8B902A6D8ACD719C40020B9E24`
- status: `partial_success`

## scope and threat model

The package covers the Korean catalog/runtime contracts, transactional yt-dlp maintenance, a Release x64 candidate assembled from an isolated source copy and reviewed dependency archive, and a localhost-only synthetic-media artifact smoke. The smoke binds only to `127.0.0.1`; it uses no credentials, browser profile, proxy, external media, or external download archive.

`File.Replace` is the one-file atomic primitive. The sibling journal provides in-process/restart recovery for the executable/provenance pair. Power-loss durability is not claimed because the implementation does not call `FileStream.Flush(true)`.

Automation output is intentionally classified `artifact-only`. It proves candidate process startup, localhost extraction, MP3 existence, hash, size, duration, and no `.part`; it does not prove GUI URL entry, information lookup, MP3 selection, download click, translated dialogs, or DPI observations.

## changed-files evidence

- exact command: `git -c safe.directory=C:/Users/ceo/OneDrive/Desktop/01_AllWork/ytdlp-interface diff --binary 2173316ebb5e50af49a2a4e939693fa8c3a3459c > review/evidence/comparison-base-to-worktree-20260813T1535Z.patch`
- patch length: `515794`
- patch SHA-256: `4640A5DBD9634F87C8624CDAF1DFD7A97A02BAE2CCBFEFCED567357626F7F2EA`
- status SHA-256: `A1CCFDBFC09E8231F048C438A3C9CCA7B7EA2F40476EC6ACAACCA592F90C3A41`
- untracked evidence files are enumerated by the evidence ledger. This spec and the ledger itself are excluded from self-hashing to avoid a circular digest.

## tests and evidence quotes

### E1 — PowerShell regression perimeter

- command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1`
- log: `review/evidence/powershell-tests-20260813T1534Z.log`
- SHA-256: `8CEFC08864B9973E3B48E41E850BFA75A8CA3734E760D3B0D65F8169DB5BE06D`
- evidence quote:

  ```text
  STARTED_AT_UTC=2026-08-13T15:33:43.1142812Z
  runtime-maintenance tests passed
  PASS runtime-maintenance.Tests.ps1
  smoke-localhost fixture tests passed.
  PASS smoke-localhost.Tests.ps1
  COMPLETED_AT_UTC=2026-08-13T15:33:54.1533938Z
  EXIT_CODE=0
  ```

### E2 — Python recovery contracts

- command: `$env:RECOVERED_CATALOG='locales/ko-KR.json'; C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe tests/run_contract_tests.py`
- log: `review/evidence/python-contract-tests-20260813T1534Z.log`
- SHA-256: `49553E1884F70245976650ECEE44E10B035098C47607D0441D325F21EBFE2DEA`
- evidence quote:

  ```text
  STARTED_AT_UTC=2026-08-13T15:33:43.0702811Z
  Ran 20 tests in 8.799s
  OK
  COMPLETED_AT_UTC=2026-08-13T15:33:52.3784108Z
  EXIT_CODE=0
  ```

### E3 — Native i18n executable

- command: `tests\native\x64\Debug\i18n_tests.exe`
- log: `review/evidence/native-i18n-tests-20260813T1534Z.log`
- SHA-256: `3587DA16F2785CAF3AE9E083BB35E0CBF7A1A986C9BBD2E0923F0444D0BE5CFB`
- evidence quote:

  ```text
  STARTED_AT_UTC=2026-08-13T15:33:43.1132808Z
  COMMAND=tests\native\x64\Debug\i18n_tests.exe
  COMPLETED_AT_UTC=2026-08-13T15:33:43.4989306Z
  EXIT_CODE=0
  ```

### E4 — Whitespace gate

- command: `git -c safe.directory=C:/Users/ceo/OneDrive/Desktop/01_AllWork/ytdlp-interface diff --check`
- log: `review/evidence/git-diff-check-20260813T1534Z.log`
- SHA-256: `96A1DD01333185A714A3EFD7A3F8F8153EC25A85BDDD18D74422954422B4A2C9`
- evidence quote:

  ```text
  STARTED_AT_UTC=2026-08-13T15:33:43.1308103Z
  COMMAND=git -c safe.directory=C:/Users/ceo/OneDrive/Desktop/01_AllWork/ytdlp-interface diff --check
  COMPLETED_AT_UTC=2026-08-13T15:33:43.7691050Z
  EXIT_CODE=0
  ```

Git also emitted LF-to-CRLF conversion warnings; they are retained in the raw log.

### E5 — Release x64 candidate build

- wrapper command and absolute arguments: `review/evidence/build-candidate-20260813T1528Z.status.json`
- status SHA-256: `991747AD04256D2B44A79257B1C92A9ECD935487DE8F3857305C3A9BFB832F63`
- stdout SHA-256: `47518719C0991964613EC815CFD1315BB3E8F153F013BBAE19586A3191C4428B`
- stderr SHA-256: `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` (empty)
- candidate root: `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-candidates\candidate-dc08eec8638f433b835ce6a5520499b1`
- packaged candidate manifest: `review/evidence/candidate-dc08-manifest-20260813T1531Z.json`
- candidate manifest SHA-256: `1070737848C63B7477BE2C053D21E48865BEF6E0807297D5BB1A69457846535E`
- evidence quote:

  ```text
  startedAtUtc: 2026-08-13T15:27:52.6418950Z
  completedAtUtc: 2026-08-13T15:31:03.8019462Z
  exitCode: 0
  exception: null
  CandidateRoot: ...\candidate-dc08eec8638f433b835ce6a5520499b1
  ```

The manifest records source commit/status, reviewed dependency archive SHA-256, four linker-input hashes, MSBuild/CMake identities, six normalized build commands, eight runtime-file hashes, and runtime versions. A node-reuse MSBuild child remained after its parent exited; its parent absence was verified and only that orphan PID was terminated after build status `exitCode=0` was written.

### E6 — Artifact-only localhost smoke

- command script: `review/evidence/run-artifact-smoke-20260813T1533Z.ps1`
- raw log: `review/evidence/artifact-smoke-20260813T1533Z.log`
- raw log SHA-256: `63C0E9DF4CB9E36117C13876F2A4795C1CCC80387CA9FF29D1F615C50C5A5F76`
- packaged run manifest: `review/evidence/candidate-dc08-smoke-79f316-20260813T1532Z.json`
- run manifest SHA-256: `AFBB52FB9B6E667DC55A4C1973A9923DBE425BD60064B36EF065268655DCAC34`
- evidence quote:

  ```text
  STARTED_AT_UTC=2026-08-13T15:32:36.8487999Z
  CANDIDATE_MANIFEST_SHA256=1070737848C63B7477BE2C053D21E48865BEF6E0807297D5BB1A69457846535E
  {"Valid":true,"ReasonCode":"ok",..."Duration":2.020136}
  COMPLETED_AT_UTC=2026-08-13T15:32:57.4513018Z
  SMOKE_EXIT=0
  ```

The append-only run manifest records `succeeded=true`, `reasonCode=ok`, `mode=artifact-only`, the same candidate manifest hash, output SHA-256 `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`, length `9328`, and duration `2.020136`.

### E7 — Parent provenance

- parent runtime: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface`
- packaged current provenance: `review/evidence/parent-yt-dlp-provenance-20260813T1536Z.json`
- current provenance SHA-256: `686DC7D0C34F088BA9499EE1A6F553CCEB521C5D05DE7828DCA537DFB55E5440`
- packaged original migration backup: `review/evidence/parent-provenance-migration-backup-20260813T1430Z.json`
- migration backup SHA-256: `5B242A27EC412468FACA9FE5A0975BBEB8488D835CB1EF1AEC9C3F8DE0336A6D`

The current provenance binds the official nightly current executable and the prior executable's version/hash/backup path. The migration preserved the original provenance bytes and did not replace an executable or perform a network download.

## self-confessed risks

1. description: GUI-internal Korean startup, URL entry, information lookup, MP3 selection, download click/completion, translated dialogs/state behavior, settings JSON close, and 100/150/200 DPI observations are not proven.
   - severity: high
   - handling: `accepted_unresolved`
   - evidence: Computer Use initialization repeatedly failed before window enumeration with `EPERM: operation not permitted, lstat 'C:\Users\ceo\AppData\Local\OpenAI\Codex'`. Kernel reset and retry produced the same error. No UI input occurred. Artifact-only evidence is not a substitute.
2. description: the worktree is dirty and the candidate manifest records `dirty=true` plus porcelain status rather than a clean commit.
   - severity: medium
   - handling: `safeguard`
   - evidence: the frozen comparison-base patch and status file bind all tracked changes; release approval still requires a reviewed clean commit and fresh candidate.
3. description: this package has not yet received the mandated final verdict from a different session or model.
   - severity: high
   - handling: `plan`
   - evidence: independent same-thread subagents audited the package and found the GUI/session blocker, but they do not satisfy `different_session_or_model`.
4. description: the supervising shell emits a PowerShell profile execution-policy warning after some elevated observations.
   - severity: low
   - handling: `accepted_unresolved`
   - evidence: every build/test/smoke child uses `-NoProfile -ExecutionPolicy Bypass`; raw logs and status JSON contain their own exit values.

## reviewer request

Verify the evidence ledger and frozen patch first. Re-run E1–E6 from the absolute commands. Do not issue NOT GUILTY unless a different session/model also captures a supervised GUI action/refresh chain for the complete Korean UI flow and confirms the operator-guided smoke manifest, fresh MP3, FFprobe output, no `.part`, settings JSON, and DPI observations.
