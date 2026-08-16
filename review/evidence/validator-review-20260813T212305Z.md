# Strict GUI execution-overlay validator review

## Scope

Only `src/tools/smoke-localhost.ps1` and its PowerShell fixture tests were changed. The sealed candidate root and all candidate payloads were not modified. The validator is external smoke infrastructure; it is not embedded in `ytdlp-interface.exe`.

## TDD evidence

- RED was observed before implementation: `Assert-SmokeExecutionOverlay` was not defined; the test runner then reported the explicit contract failures “Smoke must expose a strict execution-overlay validator” for both new tests and exited 1. The production function did not exist at that point.
- GREEN seal-red raw: `validator-green-seal-red-20260813T212243Z.raw.log`, command timestamp `2026-08-13T21:22:43.6363670Z`–`21:22:45.5999576Z`, exit 0.
- GREEN full PowerShell raw: `validator-green-full-powershell-20260813T212250Z.raw.log`, command timestamp `2026-08-13T21:22:50.4727950Z`–`21:23:00.7553601Z`, exit 0. Both runtime-maintenance and smoke-localhost suites pass.
- Diff-check raw: `validator-diff-check-20260813T212305Z.raw.log`, command timestamp `2026-08-13T21:23:05.8024126Z`–`21:23:05.8564220Z`, exit 0.

## Static review findings

1. Base binding is checked against the exact base-root manifest SHA and the copied execution manifest SHA. The base manifest also passes the existing full seal validator.
2. Non-settings payload inventory is compared by normalized relative path, byte length, and SHA-256. Missing/extra/mutated files fail with `candidate_execution_payload_changed`.
3. Settings overlay is explicit: only top-level `outpath` may differ; all other JSON content is canonicalized and must match. The output path must equal the expected smoke output directory.
4. Pre-run and post-run attestations are both recorded. Post-run validation occurs after output/FFprobe validation and before success evidence is retained, so a payload mutation cannot be reported as a successful run.
5. The validator does not alter the sealed candidate. `Set-SmokeCandidateOutputPath` still runs only on the copied execution tree.

## Edge case requiring follow-up

The validator should additionally reject an execution path equal to, or contained by/containing, the base candidate root. The normal `Copy-SealedCandidateForSmoke` path is a workspace child and the existing parent/workspace overlap guards protect the production path, but the public validator itself currently accepts an explicitly supplied same-root path if its settings overlay is valid. Add a one-test path-overlap guard before any further GUI run.

## Rebuild recommendation

No C++/GUI rebuild is required merely to validate this PowerShell infrastructure change: the validator is sourced from `src/tools/smoke-localhost.ps1` and the sealed candidate remains untouched. A new candidate build/manifest is required before distributing these source changes as a candidate or claiming that a future GUI run used a candidate containing them. The next GUI evidence run must use a fresh execution copy, run the pre/post validator against that exact process directory, and retain the resulting execution attestation.
