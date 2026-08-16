# Korean i18n recovery — F526 candidate v2 append-only package

Capture time: `2026-08-13T20:33:16.2966026Z`.

This is a new append-only package. It does not overwrite or supersede v1
artifacts. The sealed candidate is
`C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-4\candidate-2ccc31fd803f47179fe7487f5f084b93` with manifest SHA-256
`F5263136E613A81A58B998D00A46732ED793234D6CE127E6FD5C2934DD428057`.

## Required protocol metadata

- `review_target`: commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`, branch `codex/korean-i18n-recovery`, source `dirty=false`, tree SHA `07D5889D48E55B866698777D5EBD22DDFF7DE8F4E8CABB7C4451B5CFA53D7A27`.
- `comparison_base`: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`.
- `changed_files_or_diff`: `git diff --name-status 2173316ebb5e50af49a2a4e939693fa8c3a3459c..6fe72b7f2b5240c272f4e4e6244a07c76695645b`; 104 paths (75 added, 29 modified, 0 deleted, 0 renamed). Binary patch: `review/evidence/comparison-base-to-final-20260814T193500Z.patch`, 2,750,358 bytes, SHA-256 `0A683E31236CF28513B90C65F278ADDDF4AFC2324506B91E929EC77025B3E2AF`.
- `reviewer_access_assumption`: a different session/model can read this file, the companion JSON index, Git history, constitution files, candidate root, Downloads smoke run, and absolute evidence paths. No prior chat state is required.
- `meta.evidence_package`: `review/evidence/final-index-20260813T203316Z-F526.json`; exact raw evidence paths and hashes are recorded there.
- `review_package`: `partial`.
- `reviewer_required`: `different_session_or_model`.
- `status`: `partial_success`.

## Constitution

Applicable repository constitution:
`C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\AGENTS.md`,
10,453 bytes, SHA-256
`4E22E0747C79B2AD9F17F08FE7F083035F3F37C6765DD02E9AAD029DAE2BA322`.
Inherited constitution:
`C:\Users\ceo\OneDrive\Desktop\01_AllWork\AGENTS.md`, 9,613 bytes,
SHA-256 `50407D74E8897E2D4F7413ED089AAFDAD2C7658365804755164141C40A63A66C`.
No `GEMINI.md` or `CLAUDE.md` was found in those stated paths; no unsubmitted
constitution path is inferred.

## Code, build, and seal evidence

- Candidate build raw log: `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\build-candidate-final-20260814T-new.raw.log`, SHA-256 `BA841CE24F5578CEC61537DA1CD7C9D6616F68D9C34AB0669C57E145106A790A`; `SOURCE_HEAD=6fe72b7...`, `SOURCE_STATUS=`, `EXIT_CODE=0` at `2026-08-13T20:13:03.7359634Z`.
- Candidate seal recheck: `candidate-recheck-20260814T-new.json`, SHA-256 `BC1FB92F25FF2353982242920365C8CA26026EA83F31F64A7EFAC1721B92CC55`; raw validator log SHA-256 `DA956565CFC9A661B58164E08E0A72F69C28D354D2D1C4A567479C9E907CD6EF`; `Assert-CandidateManifestSeal passed`, `ENTRY_COUNT=8`, `ALL_MATCHED=True`, `EXIT_CODE=0`.
- Native raw log SHA-256 `DB10640B6DA697AD57A0AC4D7BDE9ACC2264632A01620F94AD00726AE021E742`: `BUILD_EXIT=0`, `TEST_EXIT=0`.
- Contract raw log SHA-256 `7D7C1762CA8B9F2B5419CD89B92144FE0F463451C200F36D7E7A9DC120403950`: `Ran 20 tests in 8.161s`, `OK`, `EXIT_CODE=0`.
- PowerShell raw log SHA-256 `711CFFF45BBED6A07BA6C00EE23B1C2E1E0697121523E43055A9493A49FCEA01`: runtime-maintenance and smoke-localhost fixtures passed, `EXIT_CODE=0`.

## Artifact smoke

Successful run `6808a14bf971476c875e8f4caadc6cb8`:

- manifest: `C:\Users\ceo\Downloads\ytdlp-interface-smoke-evidence\runs\6808a14bf971476c875e8f4caadc6cb8.json`, SHA-256 `82B8AF68DA37426B213890255783B639E915EAC96C6154A3DE58305EF0FC540D`;
- candidate binding: `F5263136E613A81A58B998D00A46732ED793234D6CE127E6FD5C2934DD428057`;
- mode: `artifact-only`; `succeeded=true`, `artifactValidated=true`, `guiInteractionProven=false`, `operatorAttested=false`, `cleanupSucceeded=true`;
- MP3: 9,328 bytes, SHA-256 `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`;
- settings overlay: SHA-256 `C34C81927D5E2E91D81AAD40D7B616D4EBD0199EEFFC0C39B450C1C6511D24ED`;
- FFprobe: SHA-256 `312A974BFE98206258E69671AE8F50CDAA44C2C1BD1D55BB944A4F5C0ECCC41A`, output `codec_name=mp3`, `duration=2.020136`;
- no `.part` files: true;
- raw smoke log SHA-256 `80B7B897975E116E5E648E91B7A9ECDAC3FC1BB07794825CB68E7CB3E97A1151`, status SHA-256 `BD81E240F623B0B13F9C57752FA85AC68A97A60F4D753AB6C68D60DE7843F6D5`, both exit 0.

Two failed attempts remain preserved: the 20:04 run failed `parent_runtime_required` (status SHA `32CE4FB53FDA3CB7ED2681EEFAE66A6CC71AE5AA4194697A690D4632C24DE8C6`, log SHA `CA366C42BCBFAF2ABAEF85A1FF294CEC076D1B6BE8090599AF050E3EE3857B76`); the 20:05 run failed `candidate_manifest_mismatch` against the older 22A candidate (status SHA `42096218F86B69CC9CECECA7309CDE8FA4A06C1EA60E22AA74E78D606FAE90D2`, log SHA `09032656B1755CE0A7EB58F84D1AF1B9BC4054480AAD1B8034EE0CE9FFFDE3E2`).

## GUI evidence

The new ledger is [gui-ledger-F5263136-v2.jsonl](C:/Users/ceo/OneDrive/Desktop/01_AllWork/ytdlp-interface/src/review/evidence/gui-ledger-F5263136-v2.jsonl), 14 JSONL events, SHA-256 `C34BD3F03128268CDA5E3653F7DA173F7E64748C0A9E252940E80553DF399FE7`. Every event has `preObservation` and `postObservation` fields, candidate SHA, UTC timestamp derived from screenshot mtime, window ID `33161530`, visible result, and `externalOverlayPresent=true`.

Observed states include Korean startup, settings, SponsorBlock, interface settings, URL row, metadata playlist row, playlist context/selection, direct media queue, direct context menu, sections dialog, Korean validation message, and format dialog with input/mp4 row. The direct context menu visibly contains `구간 다운로드` and `자막 선택(0/0)`.

The startup event necessarily has `preObservation=null` because it is the initial process observation; this is explicit rather than fabricated. All retained screenshots include the Codex evidence overlay. Consequently overlay-free visual proof is not claimed.

## Configuration audit

`review/evidence/codex-config-audit-20260814T200000Z.json` is 561 bytes,
SHA-256 `50A2F29D05CF4B896FAC180ECE904008CD8A397B87EC64EFB0DA517336E6E52C`.
It records config SHA-256
`EE4D7ED863CCDDE4890B450B12095C997416D553F7453EB6C7624D819B8565A1`,
`approval_policy=never`, `default_permissions=:danger-full-access`,
`windows.sandbox=elevated`, `web_search=live`, `sandbox_mode=absent`, and
`edit_performed=false`. No config edit is part of this candidate.

## Threat model

Trust boundaries are network/proxy, file I/O, process execution,
deserialization, environment/tool discovery, and local runtime replacement.
Trusted inputs are the comparison-base Git object, reviewed dependency SHA,
validated catalog, sealed candidate after manifest/hash/version recheck, and
smoke artifacts after direct hash/FFprobe checks. Untrusted inputs include
network metadata before hash/version verification, archive entries before
traversal checks, stale settings paths, translated captions as state, arbitrary
fixture output, GUI screenshots with an external overlay, and child success
before direct exit-code inspection. No auth, secret, token, proxy credential,
permission, eval, SQL, or environment-secret boundary was expanded.

## Risks and open gates

1. **High — DPI open:** manual Windows Display Scale observations at 100%,
   150%, and 200% are absent. `handling=accepted_unresolved`.
2. **High — independent review open:** no different-session-or-model verdict
   over this exact F526 package exists. `handling=plan`.
3. **High — GUI/smoke causality boundary:** the smoke run is intentionally
   artifact-only and records `guiInteractionProven=false`; GUI observations
   are separately ledgered and are not silently promoted to smoke causality.
   `handling=safeguard`.
4. **Medium — overlay:** all GUI screenshots contain an external evidence
   overlay. `handling=safeguard`.
5. **Medium — failed attempts:** both earlier 22A failures are retained rather
   than hidden. `handling=safeguard`.
6. **Medium — inventory lag:** the old untracked inventory predates v2 files;
   a future frozen package should issue a new inventory. `handling=plan`.
7. **Medium — full diff-check:** full check exits 2 on old review evidence;
   source-only check exits 0. `handling=safeguard`.

## Disposition

`partial_success` is the only supported status for this snapshot. Native,
contract, PowerShell, candidate seal, artifact smoke, and many Korean GUI
state observations are evidenced. Manual DPI tiers and independent review are
not evidenced; the successful artifact smoke itself does not claim GUI
interaction proof. Therefore this package does not claim `success` or
`NOT GUILTY`.

