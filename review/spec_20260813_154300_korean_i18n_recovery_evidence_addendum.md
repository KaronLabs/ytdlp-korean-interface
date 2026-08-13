# Korean i18n recovery — evidence addendum

This append-only addendum supersedes only the evidence index in `review/spec_20260813_153800_korean_i18n_recovery_final_package.md`. All disclosed GUI, clean-worktree, and different-session risks remain unresolved.

## updated evidence index

- created_at_utc: `2026-08-13T15:43:00Z`
- evidence ledger: `review/evidence/evidence-ledger-20260813T1542Z.json`
- ledger schema: `2`
- ledger entries: `35`
- ledger SHA-256: `2C30C1DC75326ABB7181F7B8D21CAC69DB1502A5FFA22E1B355072BF4458C17D`
- untracked inventory: `review/evidence/untracked-files-inventory-20260813T1541Z.json`
- untracked inventory SHA-256: `37C5972D8FB149189505791C8FB7BC348958A60FE256F078A11D8D6F8057008D`
- enumerated untracked files: `41`; the inventory excludes only itself to avoid a circular digest

## E6 replacement — artifact body and outer invocation

- exact outer command and output: `review/evidence/artifact-smoke-20260813T1540Z.log`
- status JSON: `review/evidence/artifact-smoke-20260813T1540Z.status.json`
- runner source: `review/evidence/run-artifact-smoke-20260813T1540Z.ps1`
- preserved MP3: `review/evidence/artifact-smoke-20260813T1540Z.mp3`
- append-only smoke manifest: `review/evidence/candidate-dc08-smoke-f7d88a-20260813T1540Z.json`
- smoke manifest SHA-256: `DD33CE7136DFB204E5A3D7BD7496F2B32EEA9E840318040B6F004E1C3E3DCFDC`
- MP3 SHA-256: `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`
- MP3 length: `9328`
- duration: `2.020136`

Evidence quote:

```text
COMMAND=powershell.exe -NoProfile -ExecutionPolicy Bypass -File review\evidence\run-artifact-smoke-20260813T1540Z.ps1 ...
STARTED_AT_UTC=2026-08-13T15:39:18.9293638Z
CANDIDATE_MANIFEST_SHA256=1070737848C63B7477BE2C053D21E48865BEF6E0807297D5BB1A69457846535E
ARTIFACT_SHA256=188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5
ARTIFACT_LENGTH=9328
OUTER_EXIT_CODE=0
completedAtUtc: 2026-08-13T15:39:38.4126654Z
exitCode: 0
exception: null
```

The packaged MP3 bytes independently hash to the same value recorded in the smoke manifest. The smoke remains `artifact-only` and is not GUI evidence.

## E7 supplement — prior executable version

- log: `review/evidence/parent-backup-version-20260813T1541Z.log`
- procedure: hash the provenance-recorded backup, copy it to a unique temporary `.exe`, run `--version`, compare output with `previousVersion`, then delete only the temporary copy

Evidence quote:

```text
STARTED_AT_UTC=2026-08-13T15:40:05.4278945Z
EXPECTED_SHA256=0B6BD5752A3C66F3FB781EF0601501F5FD3ECE2A4A57BD98FB19B08EE860786B
ACTUAL_SHA256=0B6BD5752A3C66F3FB781EF0601501F5FD3ECE2A4A57BD98FB19B08EE860786B
OUTPUT=2026.05.16.233954
EXPECTED_VERSION=2026.05.16.233954
EXIT_CODE=0
COMPLETED_AT_UTC=2026-08-13T15:40:08.8120304Z
```

## unchanged blockers

1. `different_session_or_model` final review has not occurred.
2. The complete supervised Korean GUI flow, settings/dialog/state behavior, and 100/150/200 DPI evidence do not exist because Computer Use fails before window enumeration with the repeated `EPERM lstat` error.
3. The candidate was built from a dirty worktree. A reviewed clean commit and fresh candidate are still required for release approval.

Status remains `partial_success`; this addendum does not request NOT GUILTY without those three conditions.
