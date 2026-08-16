# Strict GUI execution-overlay validator review v3

This append-only note supersedes neither prior validator notes nor any candidate package. It corrects the raw-log references so the full test artifact includes the complete observed output, including PowerShell What-if lines.

## Source and candidate integrity

- `src/tools/smoke-localhost.ps1`: 34,795 bytes, SHA `63A2CB8D18CC02CE217EBC2C1D7F73A6A9E01FCB5B95DFB469C141AA8C54CBE7`.
- `src/tests/powershell/smoke-localhost.Tests.ps1`: 85,097 bytes, SHA `454D73A40AFD2B127FA51BB00D5ABD2FD4C4FEF54D6AE0AE94D93253ED517712`.
- Sealed candidate remains manifest SHA `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`; its settings remain 12,531 bytes / `9D52BD66A45FDA25E257A9D89184C27896A44484412F2B32CD37E99FE3DB9F05`.

## Exact verification artifacts

- Overlap RED: `validator-red-overlap-20260813T212341Z.raw.log`, SHA `A1AA9C0CA09A7E02AF3A97C3ADA0E73EE53757BEA14089C1003877364A9E3178`, exit 1. The new test expected `candidate_execution_base_overlap` and observed `no_failure` before the guard.
- Seal-red GREEN: `validator-green-seal-red-v3-20260813T212357Z.raw.log`.
- Full PowerShell GREEN exact output: `validator-green-full-powershell-v3-20260813T212404Z.raw.log` (includes every captured output line, not a summary).
- Diff-check: prior `validator-diff-check-20260813T212305Z.raw.log`, exit 0; PowerShell parser reported zero syntax errors for both changed files.

## Review conclusion

The strict validator now performs exact base manifest binding, rejects any base/execution path overlap, allows only the intended `outpath` settings overlay, validates every non-settings payload by hash and length, and records pre/post attestation. Full fixture tests pass. No C++ rebuild is required for the external script change; a fresh candidate build/manifest is required before distributing a candidate that contains these source changes, and a fresh GUI run is required before any new GUI admissibility claim.
