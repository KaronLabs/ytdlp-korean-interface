# Korean i18n recovery — fresh evidence package (append-only)

## Meta

- `created_at_utc`: `2026-08-13T18:33:00Z` (package assembled after the fresh GUI run)
- `review_target`: source commit `366dc65539bec11edf8159d05b470e0beeddee6b`; candidate was built with `source.dirty=false`.
- `comparison_base`: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`
- `changed_files_or_diff`: `review/evidence/comparison-base-to-head-20260814T182700Z.patch`, 1,392,781 bytes, SHA-256 `1560E47995C287A3452DF204AC7D8E4BABFB9B689C932360A765665A22D83F70`.
- `reviewer_access_assumption`: another session/model can read the absolute evidence paths and recompute every listed SHA-256; no trust in author summaries is assumed.
- `constitution_path`: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\AGENTS.md` (present and applicable).
- `candidate_root`: `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-2\candidate-3fae2c2b8fb342e4a0a6f44dff35c185`
- `candidate_manifest_sha256`: `78E1AF2D6FBB5BC2300A7C0FE307A28AA6CA4A04160A8D8ECEAABF371205474D`
- `candidate_tree_sha256`: `B279BBA9AA63C9A1BB90CE0295A0E481D1127DCBAC48F6531976BAE12948CB61`
- `candidate_file_recheck`: 8/8 manifest entries matched length and SHA; independent `Assert-CandidateManifestSeal` returned `PASS`.
- `review_package`: `partial` — code/diff, constitution, candidate attestation, raw test logs, GUI ledger, and smoke manifest are present; mandatory 150/200% DPI observations and an independent final verdict are not yet present.
- `reviewer_required`: `different_session_or_model`
- `status`: `partial_success`

## Evidence quotes

All commands below were executed with absolute paths and their raw logs retain UTC start/end and exit code.

1. `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\build-candidate-final-20260813T180200Z.log` — build command used `powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\tools\build-candidate.ps1 -Run ...`; `END_UTC=2026-08-13T18:05:46.2160131Z`, `EXIT_CODE=0`; log SHA-256 `410A44CE1996729B15AAD799B05C8D335A7938BC99310DA8FBE3DFAE99CE8991`.
2. `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\tests-final-20260813T182300Z.log` — `runtime-maintenance tests passed`, `smoke-localhost fixture tests passed`, `EXIT_CODE=0`; SHA-256 `7BE840CDEEA5627968DF93B8D05BFBB34CC75AF5D859FA1CE175B6B871C84208`.
3. `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\contract-tests-final-20260813T182400Z.log` — `Ran 20 tests ... OK`, `EXIT_CODE=0`; SHA-256 `76DECA782CA9C26A7B8E9F2A41CC81AB01F36FEF63721D4C870E77FB58F6E396`.
4. `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\native-tests-final-20260813T182500Z.log` — native executable command and `EXIT_CODE=0`; SHA-256 `511D3897D4209EDD3EC6841126C3C570301F7941CC699E7F8C0077CCADD897FB`.
5. `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\diff-check-final-20260813T182600Z.log` — `git diff --check ...`, `EXIT_CODE=0`; SHA-256 `076746F5946F387061035843369979D46DB83E4F4A9D45667196BBBFE93F0D43`.
6. GUI action ledger `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\gui-run-20260813T174200Z-ledger.jsonl`, SHA-256 `365A33D5DF40340921E4F2A8D8F400D2863F5E602C24C87885D1F1C2B63D3746`, contains fresh entries bound to manifest `78E1...474D`: startup, URL/metadata, format dialog and checked MP4 row, format apply, download started, download completed, output view, and six settings pages (yt-dlp, SponsorBlock, queue, interface, updater, presets, about). Old entries bound to invalid manifest `090160...` are excluded from this finding.
7. Operator-guided smoke run `d4c5e9cf46dd4199927ba8ebff86aa69`: raw manifest `C:\Users\ceo\Downloads\ytdlp-interface-smoke-evidence\runs\d4c5e9cf46dd4199927ba8ebff86aa69.json`, 1,764 bytes, SHA-256 `2A527006DA3DDCA5681022CD0A7956EE14B30554436737C9060D05D1026203D5`. It records `succeeded=true`, `reasonCode=ok`, `mode=operator-guided`, `cleanupSucceeded=true`, candidate manifest binding `78E1...474D`, `artifactValidated=true`, `operatorAttested=true`, and `guiInteractionProven=false`.
8. Retained smoke artifacts: MP3 9,328 bytes SHA-256 `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`; settings JSON 8,470 bytes SHA-256 `13CFB47E0F36FE678738DC98B50C6FF4FB87675FE602E906CD6406D68045CC68`, parses as `language=ko-KR` and unique output path; raw ffprobe 33 bytes SHA-256 `312A974BFE98206258E69671AE8F50CDAA44C2C1BD1D55BB944A4F5C0ECCC41A`, content `codec_name=mp3` and `duration=2.020136`; no `.part` files. The retained bodies are outside the deleted smoke workspace.
9. Current desktop observation `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\dpi-observed-20260813T183000Z.log`, SHA-256 `9E5DDBB9229EC3C42C94EAE275A6404FA349E2FA50094F06AA0F695AED4EC880`, reports `PixelsPerXLogicalInch=120` and `PixelsPerYLogicalInch=120` for both monitors. No 150% or 200% display-scaling run was performed.

## Compliance matrix

- Korean startup and core URL→metadata→format→download→completion: demonstrated in the fresh Computer Use ledger and screenshots bound to `78E1...474D`.
- Output and settings persistence: demonstrated by the retained MP3, ffprobe, no-part listing, and post-close JSON parse/hash. The run used a disposable execution-copy settings overlay; the sealed candidate remained unchanged.
- Runtime, build attestation, hermetic command semantics, and contract tests: demonstrated by the fresh raw logs and the independent candidate seal recheck.
- DPI 100/150/200 acceptance: incomplete. Only the current 120 logical DPI desktop was observed; changing Windows display scaling requires an explicit user/manual action and was not performed.
- Independent review: pending. This package explicitly requires a different session or model and does not treat the current author session as independent.

## Risks and handling (self-confessed)

1. High — 150/200% DPI evidence absent. `handling=accepted_unresolved`; remediation is a new append-only spec after user/manual scaling and fresh Computer Use observations.
2. High — different-session/model verdict absent at package creation. `handling=plan`; no NOT GUILTY claim is made before that verdict.
3. Medium — operator smoke's `guiInteractionProven=false` is intentional. `handling=safeguard`; GUI screenshots/action ledger are kept separate from artifact validation and the manifest is not misread as causal GUI proof.
4. Low — execution-copy settings hash differs from sealed candidate. `handling=safeguard`; overlay is outside the sealed candidate and is bound by the smoke execution attestation.

## Provisional disposition

The implementation and the tested 100%-scale path are materially functional, but the submission does not satisfy every mandatory review slot. Under the supplied protocol, `partial_success` cannot be promoted to NOT GUILTY while DPI tiers and independent review remain open. The objective defect is incomplete acceptance evidence, not a claim that the tested core path failed.
