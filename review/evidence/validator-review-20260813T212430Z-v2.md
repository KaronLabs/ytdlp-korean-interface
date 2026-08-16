# Strict GUI execution-overlay validator review v2

## Current source hashes

- `src/tools/smoke-localhost.ps1`: 34,795 bytes, mtime `2026-08-13T21:23:52.0691285Z`, SHA-256 `63A2CB8D18CC02CE217EBC2C1D7F73A6A9E01FCB5B95DFB469C141AA8C54CBE7`.
- `src/tests/powershell/smoke-localhost.Tests.ps1`: 85,097 bytes, mtime `2026-08-13T21:23:36.4390334Z`, SHA-256 `454D73A40AFD2B127FA51BB00D5ABD2FD4C4FEF54D6AE0AE94D93253ED517712`.

The sealed candidate root was not touched. These are external PowerShell infrastructure and fixture-test changes only.

## TDD RED/GREEN

- New overlap test RED: `validator-red-overlap-20260813T212341Z.raw.log`,  `2026-08-13T21:23:41.6936524Z`–`21:23:43.7502020Z`, exit 1. The validator returned `no_failure` when execution root equaled base root, proving the test caught the missing guard.
- GREEN seal-red: `validator-green-seal-red-v2-20260813T212357Z.raw.log`, `2026-08-13T21:23:57.2149486Z`–`21:23:59.0195550Z`, exit 0.
- GREEN full PowerShell: `validator-green-full-powershell-v2-20260813T212404Z.raw.log`, `2026-08-13T21:24:04.2259048Z`–`21:24:15.1611331Z`, exit 0. Both runtime-maintenance and smoke-localhost suites pass.

## Final behavior

`Assert-SmokeExecutionOverlay` now rejects base/execution path overlap with `candidate_execution_base_overlap`, verifies exact base and execution manifest SHA binding, compares all non-settings payload hashes/lengths, allows only `outpath` to differ in settings, and records pre/post attestations. The production smoke path invokes it before starting the GUI and after output/FFprobe validation, before retaining success evidence.

## Rebuild recommendation

No C++/GUI rebuild is required to test or deploy this external validator script itself; all fixture tests pass and the sealed candidate is unchanged. A new candidate build/manifest is required before distributing a candidate that is supposed to include these source changes, and a fresh GUI run is required before making any GUI-admissibility claim. That run must use the updated script, a fresh execution copy, pre/post overlay attestation, and a post-capture inventory.

## Remaining caveat

The validator is strict for the normal copy-to-workspace flow. Its settings comparison intentionally permits only top-level `outpath`; any future legitimate settings overlay must be encoded as a separately tested allowed field rather than silently broadened.
